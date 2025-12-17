import AppKit
import Foundation
import SwiftData

@MainActor
final class DownloadViewModel: ObservableObject {
    enum Filter: Hashable, CaseIterable {
        case all
        case active
        case completed
        case failed
        case category(DownloadCategory)

        static var allCases: [Filter] { [.all, .active, .completed, .failed] }

        var title: String {
            switch self {
            case .all: return "All"
            case .active: return "Active"
            case .completed: return "Completed"
            case .failed: return "Failed"
            case .category(let category): return category.rawValue.capitalized
            }
        }
    }

    @Published var downloads: [DownloadItem] = []
    @Published var filter: Filter = .all
    @Published var isMonitoringClipboard = false
    @Published var searchQuery = ""

    private let engine: DownloadEngine
    private var clipboardTimer: Timer?
    private weak var modelContext: ModelContext?
    private var recentlyRemoved: Set<URL> = []

    init(engine: DownloadEngine = .shared, modelContext: ModelContext? = nil) {
        self.engine = engine
        self.modelContext = modelContext
    }

    func attach(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func loadPersisted(_ items: [DownloadItem]) {
        downloads = items.sorted { $0.createdAt > $1.createdAt }
    }

    func addDownload(from url: URL, segments: Int = 4) {
        let destination = Self.defaultDestination(for: url)
        let item = DownloadItem(
            url: url,
            filename: destination.lastPathComponent,
            destination: destination
        )

        downloads.insert(item, at: 0)
        modelContext?.insert(item)
        start(item, segments: segments)
    }

    func start(_ item: DownloadItem, segments: Int = 4) {
        Task {
            await engine.enqueue(
                item,
                segments: segments,
                onProgress: { [weak self] progress in
                    Task { @MainActor in
                        self?.handle(progress: progress)
                    }
                },
                onCompletion: { [weak self] result in
                    Task { @MainActor in
                        self?.handleCompletion(for: item.id, result: result)
                    }
                }
            )
        }
    }

    func pause(_ item: DownloadItem) {
        Task { await engine.pause(id: item.id) }
        item.state = .paused
        persistChanges()
    }

    func resume(_ item: DownloadItem, segments: Int = 4) {
        Task {
            await engine.resume(
                item,
                segments: segments,
                onProgress: { [weak self] progress in
                    Task { @MainActor in
                        self?.handle(progress: progress)
                    }
                },
                onCompletion: { [weak self] result in
                    Task { @MainActor in
                        self?.handleCompletion(for: item.id, result: result)
                    }
                }
            )
        }
        item.state = .queued
        persistChanges()
    }

    func delete(_ item: DownloadItem) {
        Task { await engine.pause(id: item.id) }
        downloads.removeAll { $0.id == item.id }
        recentlyRemoved.insert(item.url)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
            _ = await MainActor.run {
                self?.recentlyRemoved.remove(item.url)
            }
        }
        if let context = modelContext {
            context.delete(item)
            persistChanges()
        }
    }

    func filteredDownloads() -> [DownloadItem] {
        downloads.filter { item in
            switch filter {
            case .all:
                return matchesSearch(item)
            case .active:
                return (.queued == item.state || .downloading == item.state || .paused == item.state) && matchesSearch(item)
            case .completed:
                return item.state == .completed && matchesSearch(item)
            case .failed:
                return item.state == .failed && matchesSearch(item)
            case .category(let category):
                return item.category == category && matchesSearch(item)
            }
        }
    }

    func toggleClipboardMonitoring() {
        isMonitoringClipboard.toggle()
        isMonitoringClipboard ? startClipboardMonitoring() : stopClipboardMonitoring()
    }

    private func handle(progress: DownloadProgress) {
        guard let index = downloads.firstIndex(where: { $0.id == progress.itemID }) else { return }
        let item = downloads[index]

        item.progress = progress.progress
        item.bytesReceived = progress.bytesReceived
        item.totalBytes = progress.totalBytes
        item.speedBytesPerSecond = progress.speedBytesPerSecond
        item.state = progress.state
        item.chunks = progress.chunks
        item.updatedAt = .now
    }

    private func handleCompletion(for id: UUID, result: Result<URL, Error>) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        let item = downloads[index]

        switch result {
        case .success:
            item.state = .completed
            item.progress = 1
        case .failure:
            item.state = .failed
        }
        item.updatedAt = .now
        persistChanges()
    }

    private func persistChanges() {
        do {
            try modelContext?.save()
        } catch {
            // swallow persistence errors for now; UI can present retry.
        }
    }

    private func matchesSearch(_ item: DownloadItem) -> Bool {
        guard !searchQuery.isEmpty else { return true }
        return item.filename.localizedCaseInsensitiveContains(searchQuery)
        || item.url.absoluteString.localizedCaseInsensitiveContains(searchQuery)
    }

    private func startClipboardMonitoring() {
        stopClipboardMonitoring()

        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard let string = NSPasteboard.general.string(forType: .string), let url = URL(string: string) else { return }

            Task { @MainActor in
                if !self.downloads.contains(where: { $0.url == url }) && !self.recentlyRemoved.contains(url) {
                    self.addDownload(from: url)
                }
            }
        }
    }

    private func stopClipboardMonitoring() {
        clipboardTimer?.invalidate()
        clipboardTimer = nil
    }

    private static func defaultDestination(for url: URL) -> URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        return downloads.appendingPathComponent(url.lastPathComponent)
    }
}
