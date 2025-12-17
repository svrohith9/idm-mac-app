import Foundation
import SwiftData

enum DownloadState: String, Codable, CaseIterable, Sendable {
    case idle
    case queued
    case downloading
    case paused
    case merging
    case completed
    case failed
    case canceled
}

enum DownloadCategory: String, Codable, CaseIterable, Sendable {
    case documents
    case images
    case audio
    case video
    case archives
    case other

    init(fileExtension: String?) {
        guard let ext = fileExtension?.lowercased() else {
            self = .other
            return
        }

        switch ext {
        case "pdf", "doc", "docx", "txt", "rtf":
            self = .documents
        case "png", "jpg", "jpeg", "gif", "heic", "webp":
            self = .images
        case "mp3", "aac", "wav", "flac":
            self = .audio
        case "mp4", "mov", "mkv", "avi":
            self = .video
        case "zip", "rar", "7z", "tar", "gz":
            self = .archives
        default:
            self = .other
        }
    }
}

/// Track progress for one HTTP range chunk so we can resume and merge in order.
struct DownloadChunkState: Codable, Hashable, Sendable, Identifiable {
    var id: Int
    var rangeLowerBound: Int64
    var rangeUpperBound: Int64
    var receivedBytes: Int64
    var tempFilename: String

    var expectedLength: Int64 {
        rangeUpperBound - rangeLowerBound + 1
    }

    var isComplete: Bool {
        receivedBytes >= expectedLength
    }
}

@Model
final class DownloadItem: Identifiable {
    @Attribute(.unique) var id: UUID
    var url: URL
    var filename: String
    var destination: URL
    var state: DownloadState
    var progress: Double
    var bytesReceived: Int64
    var totalBytes: Int64?
    var speedBytesPerSecond: Double
    var category: DownloadCategory
    var createdAt: Date
    var updatedAt: Date

    // Persist chunk metadata as encoded Data; computed var exposes typed array.
    @Attribute(.externalStorage) var chunkData: Data?

    var chunks: [DownloadChunkState] {
        get {
            guard let chunkData else { return [] }
            return (try? JSONDecoder().decode([DownloadChunkState].self, from: chunkData)) ?? []
        }
        set {
            chunkData = try? JSONEncoder().encode(newValue)
        }
    }

    init(
        id: UUID = UUID(),
        url: URL,
        filename: String,
        destination: URL,
        state: DownloadState = .queued,
        progress: Double = 0,
        bytesReceived: Int64 = 0,
        totalBytes: Int64? = nil,
        speedBytesPerSecond: Double = 0,
        category: DownloadCategory? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        chunks: [DownloadChunkState] = []
    ) {
        self.id = id
        self.url = url
        self.filename = filename
        self.destination = destination
        self.state = state
        self.progress = progress
        self.bytesReceived = bytesReceived
        self.totalBytes = totalBytes
        self.speedBytesPerSecond = speedBytesPerSecond
        self.category = category ?? DownloadCategory(fileExtension: destination.pathExtension)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.chunkData = try? JSONEncoder().encode(chunks)
    }
}
