import AppKit
import SwiftUI
import SwiftData

struct DownloadCommandActions {
    var newDownload: () -> Void
    var deleteSelected: () -> Void
    var toggleSelected: () -> Void
    var focusSearch: () -> Void
}

enum DownloadCommandKey: FocusedValueKey {
    typealias Value = DownloadCommandActions
}

extension FocusedValues {
    var downloadCommands: DownloadCommandActions? {
        get { self[DownloadCommandKey.self] }
        set { self[DownloadCommandKey.self] = newValue }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DownloadItem.createdAt, order: .reverse) private var storedItems: [DownloadItem]

    @StateObject private var viewModel = DownloadViewModel()
    @State private var showingAddSheet = false
    @State private var pendingURLString = ""
    @State private var selectedID: UUID?
    @FocusState private var isSearchFocused: Bool
    @FocusState private var isURLFieldFocused: Bool

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel)
        } detail: {
            ZStack(alignment: .topTrailing) {
                mainList

                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.headline)
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                        .shadow(radius: 6, y: 2)
                }
                .buttonStyle(.plain)
                .padding()
            }
            .background(.thinMaterial)
            .sheet(isPresented: $showingAddSheet) {
                addDownloadSheet
            }
            .navigationTitle("IDM for Mac")
            .toolbarRole(.editor)
            .focusedValue(\.downloadCommands, commandActions)
        }
        .onAppear {
            viewModel.attach(modelContext: modelContext)
            viewModel.loadPersisted(storedItems)
        }
        .onChange(of: storedItems) { _, newValue in
            viewModel.loadPersisted(newValue)
        }
        .onChange(of: showingAddSheet) { _, isPresented in
            if isPresented {
                isURLFieldFocused = true
            }
        }
    }

    private var mainList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                searchField

                LazyVStack(spacing: 6) {
                    ForEach(viewModel.filteredDownloads(), id: \.id) { item in
                        DownloadRowView(
                            item: item,
                            pauseAction: { viewModel.pause(item) },
                            resumeAction: { viewModel.resume(item) },
                            deleteAction: { viewModel.delete(item) },
                            isSelected: item.id == selectedID
                        )
                        .padding(.horizontal)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedID = item.id
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
            .padding(.vertical)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: viewModel.downloads.count)
    }

    private var addDownloadSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Download")
                .font(.title2.weight(.semibold))

            TextField("https://example.com/file.zip", text: $pendingURLString)
                .textFieldStyle(.roundedBorder)
                .focused($isURLFieldFocused)
                .onSubmit(addPendingURL)
                .onAppear {
                    // Focus the field so Cmd+V works immediately.
                    isURLFieldFocused = true
                }

            HStack {
                Spacer()
                Button("Paste") { pasteFromClipboard() }
                Button("Cancel") { showingAddSheet = false }
                Button("Add") { addPendingURL() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(minWidth: 320)
        .padding()
    }

    private var searchField: some View {
        TextField("Search downloads", text: $viewModel.searchQuery)
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal)
            .focused($isSearchFocused)
    }

    private func addPendingURL() {
        guard let url = URL(string: pendingURLString) else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            viewModel.addDownload(from: url)
        }
        pendingURLString = ""
        showingAddSheet = false
    }

    private func pasteFromClipboard() {
        if let str = NSPasteboard.general.string(forType: .string) {
            pendingURLString = str.trimmingCharacters(in: .whitespacesAndNewlines)
            isURLFieldFocused = true
        }
    }

    private var commandActions: DownloadCommandActions {
        DownloadCommandActions(
            newDownload: { showingAddSheet = true },
            deleteSelected: {
                guard let id = selectedID, let item = viewModel.downloads.first(where: { $0.id == id }) else { return }
                viewModel.delete(item)
                selectedID = nil
            },
            toggleSelected: {
                guard let id = selectedID, let item = viewModel.downloads.first(where: { $0.id == id }) else { return }
                switch item.state {
                case .downloading:
                    viewModel.pause(item)
                case .completed:
                    break
                default:
                    viewModel.resume(item)
                }
            },
            focusSearch: { isSearchFocused = true }
        )
    }
}
