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
        .commands {
            IDMCommands()
        }
    }
}

struct IDMCommands: Commands {
    @FocusedValue(\.downloadCommands) private var commands

    var body: some Commands {
        CommandMenu("Downloads") {
            Button("New Download") {
                commands?.newDownload()
            }
            .keyboardShortcut("n")

            Button("Search") {
                commands?.focusSearch()
            }
            .keyboardShortcut("f")

            Button("Pause/Resume Selected") {
                commands?.toggleSelected()
            }
            .keyboardShortcut(" ", modifiers: [])

            Button("Delete Selected") {
                commands?.deleteSelected()
            }
            .keyboardShortcut(.delete, modifiers: [])
        }
    }
}
