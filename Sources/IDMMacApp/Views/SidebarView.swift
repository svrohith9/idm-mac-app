import SwiftUI

struct SidebarView: View {
    @ObservedObject var viewModel: DownloadViewModel

    var body: some View {
        List {
            Section {
                sidebarButton(.all, systemName: "tray.full")
                sidebarButton(.active, systemName: "arrow.down.circle")
                sidebarButton(.completed, systemName: "checkmark.circle")
                sidebarButton(.failed, systemName: "xmark.circle")
            }

            Section("Categories") {
                ForEach(DownloadCategory.allCases, id: \.self) { category in
                    sidebarButton(.category(category), systemName: symbol(for: category))
                }
            }

            Section {
                Toggle(isOn: $viewModel.isMonitoringClipboard) {
                    Label("Clipboard Monitor", systemImage: "doc.on.clipboard")
                }
                .onChange(of: viewModel.isMonitoringClipboard) { _, newValue in
                    viewModel.toggleClipboardMonitoring()
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(.ultraThinMaterial)
    }

    private func sidebarButton(_ filter: DownloadViewModel.Filter, systemName: String) -> some View {
        Button {
            viewModel.filter = filter
        } label: {
            HStack {
                Label(filter.title, systemImage: systemName)
                Spacer()
                if viewModel.filter == filter {
                    Image(systemName: "checkmark")
                        .font(.caption2)
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(viewModel.filter == filter ? Color.accentColor.opacity(0.1) : Color.clear)
    }

    private func symbol(for category: DownloadCategory) -> String {
        switch category {
        case .documents: return "doc.text"
        case .images: return "photo"
        case .audio: return "waveform"
        case .video: return "film"
        case .archives: return "archivebox"
        case .other: return "shippingbox"
        }
    }
}
