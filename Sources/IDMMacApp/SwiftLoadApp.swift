import SwiftUI
import SwiftData

@main
struct IDMMacApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: DownloadItem.self)
        .windowStyle(.hiddenTitleBar)
    }
}
