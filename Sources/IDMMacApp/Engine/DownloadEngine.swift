import Foundation

struct DownloadProgress: Sendable {
    let itemID: UUID
    let progress: Double
    let state: DownloadState
    let bytesReceived: Int64
    let totalBytes: Int64
    let speedBytesPerSecond: Double
    let chunks: [DownloadChunkState]
}

enum DownloadEngineError: Error {
    case invalidResponse
    case missingContentLength
    case mergeFailed
    case rangeNotSupported
}

/// Actor-backed engine responsible for multi-part HTTP downloads with resume support.
/// Each download is split into N ranges using the `Range` header. Child tasks stream bytes concurrently
/// into temporary chunk files, and the actor aggregates progress and merges the chunks when complete.
actor DownloadEngine {
    static let shared = DownloadEngine()

    private let session: URLSession
    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    private let fileManager = FileManager.default

    private var activeTasks: [UUID: Task<Void, Never>] = [:]
    private var latestChunks: [UUID: [Int: DownloadChunkState]] = [:]
    private var startTimes: [UUID: Date] = [:]

    init(session: URLSession = .init(configuration: .default)) {
        self.session = session
    }

    func enqueue(
        _ item: DownloadItem,
        segments: Int = 4,
        onProgress: @escaping (DownloadProgress) -> Void,
        onCompletion: @escaping (Result<URL, Error>) -> Void
    ) async {
        guard activeTasks[item.id] == nil else { return }

        let task = Task {
            do {
                let destination = try await performDownload(
                    item: item,
                    segments: segments,
                    onProgress: onProgress
                )
                onCompletion(.success(destination))
            } catch is CancellationError {
                // Treat cancellation (pause) as a non-error; caller will update state.
            } catch {
                onCompletion(.failure(error))
            }
        }

        activeTasks[item.id] = task
    }

    func pause(id: UUID) async {
        activeTasks[id]?.cancel()
        activeTasks[id] = nil
        latestChunks[id] = nil
        startTimes[id] = nil
    }

    func resume(
        _ item: DownloadItem,
        segments: Int = 4,
        onProgress: @escaping (DownloadProgress) -> Void,
        onCompletion: @escaping (Result<URL, Error>) -> Void
    ) async {
        // Resuming simply re-enqueues using existing chunk metadata.
        await enqueue(item, segments: segments, onProgress: onProgress, onCompletion: onCompletion)
    }

    // MARK: - Core logic

    private func performDownload(
        item: DownloadItem,
        segments: Int,
        onProgress: @escaping (DownloadProgress) -> Void
    ) async throws -> URL {
        try Task.checkCancellation()

        do {
            let head = try await fetchHead(for: item.url)

            // If the server does not support range requests or length is unknown, fall back to single-stream download.
            guard head.supportsRanges, let totalLength = head.totalBytes else {
                return try await downloadSingleStream(
                    item: item,
                    totalBytes: head.totalBytes,
                    onProgress: onProgress
                )
            }

            var chunkStates = try chunkPlan(for: item, totalBytes: totalLength, segments: segments)

            startTimes[item.id] = .now
            latestChunks[item.id] = Dictionary(uniqueKeysWithValues: chunkStates.map { ($0.id, $0) })

            let tempDir = try makeTempDirectory(for: item.id)

            // Spawn one child task per chunk to stream bytes concurrently using HTTP ranges.
            try await withThrowingTaskGroup(of: DownloadChunkState.self) { group in
                for chunk in chunkStates {
                    group.addTask { [weak self] in
                        guard let self else { throw DownloadEngineError.invalidResponse }
                        return try await self.downloadChunk(
                            for: item,
                            chunk: chunk,
                            totalBytes: totalLength,
                            tempDir: tempDir,
                            onProgress: onProgress
                        )
                    }
                }

                chunkStates.removeAll()
                for try await updatedChunk in group {
                    chunkStates.append(updatedChunk)
                }
            }

            chunkStates.sort { $0.id < $1.id }
            try mergeChunks(chunks: chunkStates, destination: item.destination, tempDir: tempDir)

            latestChunks[item.id] = nil
            activeTasks[item.id] = nil
            startTimes[item.id] = nil

            return item.destination
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Fallback: if segmented path fails, attempt single-stream download.
            return try await downloadSingleStream(item: item, totalBytes: nil, onProgress: onProgress)
        }
    }

    private struct HeadInfo {
        let totalBytes: Int64?
        let supportsRanges: Bool
    }

    private func fetchHead(for url: URL) async throws -> HeadInfo {
        // First try HEAD; if it fails or lacks info, fall back to a range probe (bytes=0-0).
        if let headInfo = try? await headRequest(url: url) {
            return headInfo
        }

        if let probeInfo = try? await rangeProbe(url: url) {
            return probeInfo
        }

        return HeadInfo(totalBytes: nil, supportsRanges: false)
    }

    private func headRequest(url: URL) async throws -> HeadInfo {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
            throw DownloadEngineError.invalidResponse
        }

        var lengthValue: Int64?
        if let length = http.value(forHTTPHeaderField: "Content-Length"), let total = Int64(length) {
            lengthValue = total
        }

        let expected = response.expectedContentLength
        if expected > 0 {
            lengthValue = expected
        }

        let supportsRanges = (http.value(forHTTPHeaderField: "Accept-Ranges")?.lowercased().contains("bytes") ?? false)
        return HeadInfo(totalBytes: lengthValue, supportsRanges: supportsRanges)
    }

    private func rangeProbe(url: URL) async throws -> HeadInfo {
        var request = URLRequest(url: url)
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DownloadEngineError.invalidResponse
        }

        let supportsRanges = http.statusCode == 206 || (http.value(forHTTPHeaderField: "Accept-Ranges")?.lowercased().contains("bytes") ?? false)

        var totalBytes: Int64?
        if let contentRange = http.value(forHTTPHeaderField: "Content-Range") {
            // Format: bytes 0-0/12345
            let parts = contentRange.split(separator: "/")
            if let last = parts.last, let value = Int64(last) {
                totalBytes = value
            }
        }

        if totalBytes == nil, let length = http.value(forHTTPHeaderField: "Content-Length"), let value = Int64(length) {
            totalBytes = value
        }

        let expected = response.expectedContentLength
        if totalBytes == nil, expected > 0 {
            totalBytes = expected
        }

        return HeadInfo(totalBytes: totalBytes, supportsRanges: supportsRanges)
    }

    // Single-stream download used when server does not support Range headers.
    private func downloadSingleStream(
        item: DownloadItem,
        totalBytes: Int64?,
        onProgress: @escaping (DownloadProgress) -> Void
    ) async throws -> URL {
        var request = URLRequest(url: item.url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (bytes, _) = try await session.bytes(for: request)
        let tempDir = try makeTempDirectory(for: item.id)
        let tempFile = tempDir.appendingPathComponent("single-\(item.id.uuidString)")

        if !fileManager.fileExists(atPath: tempFile.path) {
            fileManager.createFile(atPath: tempFile.path, contents: nil)
        }

        let handle = try FileHandle(forWritingTo: tempFile)
        defer { try? handle.close() }

        var received: Int64 = 0
        var buffer: [UInt8] = []
        buffer.reserveCapacity(32_768)

        for try await byte in bytes {
            try Task.checkCancellation()
            buffer.append(byte)

            if buffer.count >= 32_768 {
                try handle.write(contentsOf: Data(buffer))
                received += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)

                let progress = DownloadProgress(
                    itemID: item.id,
                    progress: {
                        guard let totalBytes, totalBytes > 0 else { return 0 }
                        return Double(received) / Double(totalBytes)
                    }(),
                    state: .downloading,
                    bytesReceived: received,
                    totalBytes: totalBytes ?? 0,
                    speedBytesPerSecond: 0,
                    chunks: []
                )
                await publishProgress(progress, onProgress: onProgress)
            }
        }

        if !buffer.isEmpty {
            try handle.write(contentsOf: Data(buffer))
            received += Int64(buffer.count)
        }

        try fileManager.moveItem(at: tempFile, to: item.destination)
        return item.destination
    }

    private func chunkPlan(for item: DownloadItem, totalBytes: Int64, segments: Int) throws -> [DownloadChunkState] {
        if !item.chunks.isEmpty {
            return item.chunks
        }

        // Use requested segments (capped at 8) to maximize concurrency; avoid limiting chunk size.
        let clampedSegments = max(1, min(segments, 8))
        let actualSegments = max(1, min(clampedSegments, Int(max(1, totalBytes))))
        let baseSize = totalBytes / Int64(actualSegments)
        let remainder = totalBytes % Int64(actualSegments)

        var ranges: [DownloadChunkState] = []
        var lower: Int64 = 0

        for index in 0..<actualSegments {
            let extra = index < remainder ? 1 : 0
            let upper = lower + baseSize - 1 + Int64(extra)

            ranges.append(
                DownloadChunkState(
                    id: index,
                    rangeLowerBound: lower,
                    rangeUpperBound: upper,
                    receivedBytes: 0,
                    tempFilename: "\(item.id.uuidString)-chunk-\(index)"
                )
            )

            lower = upper + 1
        }

        return ranges
    }

    private func makeTempDirectory(for id: UUID) throws -> URL {
        let dir = fileManager.temporaryDirectory.appendingPathComponent("IDMMacApp/\(id)", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func chunkURL(for tempDir: URL, chunk: DownloadChunkState) -> URL {
        tempDir.appendingPathComponent(chunk.tempFilename)
    }

    private func downloadChunk(
        for item: DownloadItem,
        chunk: DownloadChunkState,
        totalBytes: Int64,
        tempDir: URL,
        onProgress: @escaping (DownloadProgress) -> Void
    ) async throws -> DownloadChunkState {
        var mutableChunk = chunk
        let rangeStart = chunk.rangeLowerBound + chunk.receivedBytes
        let rangeValue = "bytes=\(rangeStart)-\(chunk.rangeUpperBound)"

        var request = URLRequest(url: item.url)
        request.setValue(rangeValue, forHTTPHeaderField: "Range")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (bytes, _) = try await session.bytes(for: request)
        let chunkURL = chunkURL(for: tempDir, chunk: chunk)

        if !fileManager.fileExists(atPath: chunkURL.path) {
            fileManager.createFile(atPath: chunkURL.path, contents: nil)
        }

        let handle = try FileHandle(forWritingTo: chunkURL)
        defer { try? handle.close() }
        try handle.seekToEnd()

        var buffer: [UInt8] = []
        buffer.reserveCapacity(32_768)

        for try await byte in bytes {
            try Task.checkCancellation()
            buffer.append(byte)

            if buffer.count >= 32_768 {
                try handle.write(contentsOf: Data(buffer))
                mutableChunk.receivedBytes += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)

                await updateProgress(
                    for: item.id,
                    updatedChunk: mutableChunk,
                    totalBytes: totalBytes,
                    onProgress: onProgress
                )
            }
        }

        if !buffer.isEmpty {
            try handle.write(contentsOf: Data(buffer))
            mutableChunk.receivedBytes += Int64(buffer.count)
            await updateProgress(
                for: item.id,
                updatedChunk: mutableChunk,
                totalBytes: totalBytes,
                onProgress: onProgress
            )
        }

        return mutableChunk
    }

    @MainActor
    private func publishProgress(_ progress: DownloadProgress, onProgress: (DownloadProgress) -> Void) {
        onProgress(progress)
    }

    private func updateProgress(
        for itemID: UUID,
        updatedChunk: DownloadChunkState,
        totalBytes: Int64,
        onProgress: @escaping (DownloadProgress) -> Void
    ) async {
        guard var chunks = latestChunks[itemID] else { return }
        chunks[updatedChunk.id] = updatedChunk
        latestChunks[itemID] = chunks

        let received = chunks.values.reduce(into: Int64(0)) { $0 += $1.receivedBytes }
        let progressValue = Double(received) / Double(totalBytes)

        let started = startTimes[itemID] ?? .now
        let elapsed = Date().timeIntervalSince(started)
        let speed = elapsed > 0 ? Double(received) / elapsed : 0

        let progress = DownloadProgress(
            itemID: itemID,
            progress: progressValue,
            state: progressValue >= 1 ? .completed : .downloading,
            bytesReceived: received,
            totalBytes: totalBytes,
            speedBytesPerSecond: speed,
            chunks: chunks.values.sorted { $0.id < $1.id }
        )

        await publishProgress(progress, onProgress: onProgress)
    }

    private func mergeChunks(chunks: [DownloadChunkState], destination: URL, tempDir: URL) throws {
        // Merge in order to avoid seeking; append each chunk sequentially.
        let tempDestination = destination.appendingPathExtension("partial")
        fileManager.createFile(atPath: tempDestination.path, contents: nil)

        let outHandle = try FileHandle(forWritingTo: tempDestination)

        defer { try? outHandle.close() }

        for chunk in chunks.sorted(by: { $0.id < $1.id }) {
            let chunkURL = chunkURL(for: tempDir, chunk: chunk)

            guard let inHandle = try? FileHandle(forReadingFrom: chunkURL) else {
                throw DownloadEngineError.mergeFailed
            }

            defer { try? inHandle.close() }

            while true {
                let data = try inHandle.read(upToCount: 1024 * 256)
                guard let data else { break }
                try outHandle.write(contentsOf: data)
            }
        }

        // Replace any existing file atomically.
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: tempDestination, to: destination)
    }
}
