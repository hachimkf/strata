import SwiftUI
import AppKit
import StrataCore

enum SidebarItem: Hashable {
    case all, week, review, loose
    case folder(URL)
}

struct ContentView: View {
    @EnvironmentObject var library: Library
    @ViewState private var selection: SidebarItem? = .all
    @ViewState private var path: [String] = []
    @ViewState private var search = ""

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $selection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            NavigationStack(path: $path) {
                detailRoot
                    .navigationDestination(for: String.self) { id in
                        if let project = library.project(id: id) {
                            ProjectDetailView(project: project)
                        } else {
                            ContentUnavailableView("Project not found", systemImage: "questionmark.folder",
                                                   description: Text("Its files may have been moved or deleted."))
                        }
                    }
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search projects and files")
        .onChange(of: selection) { path = [] }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { library.rescan() } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .help("Scan watched folders again (⌘R)")
                .disabled(library.isScanning)
            }
        }
    }

    @ViewBuilder private var detailRoot: some View {
        switch selection ?? .all {
        case .loose:
            LooseFilesView(files: filteredLoose)
        default:
            ProjectGridView(projects: filteredProjects, title: title, subtitle: subtitle) { path.append($0.id) }
        }
    }

    private var filteredProjects: [ProjectGroup] {
        var list = library.projects
        switch selection ?? .all {
        case .week:
            let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
            list = list.filter { $0.lastModified >= cutoff }
        case .review:
            list = list.filter(\.needsReview)
        case .folder(let url):
            list = list.filter { $0.files.contains { $0.file.path.hasPrefix(url.path + "/") } }
        default: break
        }
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return list }
        return list.filter { p in p.name.lowercased().contains(q) || p.files.contains { $0.file.name.lowercased().contains(q) } }
    }

    private var filteredLoose: [CreativeFile] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? library.loose : library.loose.filter { $0.name.lowercased().contains(q) }
    }

    private var title: String {
        switch selection ?? .all {
        case .all: return "Projects"
        case .week: return "This Week"
        case .review: return "Needs Review"
        case .loose: return "Loose Files"
        case .folder(let url): return url.lastPathComponent
        }
    }

    private var subtitle: String {
        switch selection ?? .all {
        case .review: return "Projects with crash-recovered files or exact duplicates"
        case .week: return "Projects you saved in the last 7 days"
        default: return "Most recently saved first"
        }
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @EnvironmentObject var library: Library
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            Section("Library") {
                row(.all, "All Projects", "square.stack.3d.up", count: library.projects.count)
                row(.week, "This Week", "clock", count: weekCount)
                row(.review, "Needs Review", "exclamationmark.triangle", count: library.projects.filter(\.needsReview).count)
                row(.loose, "Loose Files", "doc", count: library.loose.count)
            }
            Section("Watching") {
                ForEach(library.folders, id: \.self) { url in
                    row(.folder(url), url.lastPathComponent, "folder", count: library.projectCount(in: url))
                        .contextMenu {
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                            Button("Stop Watching", role: .destructive) { library.removeFolder(url) }
                        }
                }
                Button { addFolder() } label: {
                    Label("Add Folder…", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { status }
    }

    private var weekCount: Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        return library.projects.filter { $0.lastModified >= cutoff }.count
    }

    private func row(_ item: SidebarItem, _ title: String, _ symbol: String, count: Int) -> some View {
        Label(title, systemImage: symbol)
            .badge(count)
            .tag(item)
    }

    private var status: some View {
        HStack(spacing: 8) {
            if library.isScanning {
                ProgressView().controlSize(.small)
                Text("Scanning…")
            } else {
                Circle().fill(.green).frame(width: 7, height: 7)
                Text("\(library.fileCount.formatted()) files · read-only")
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Watch"
        panel.message = "Choose folders Strata should watch. Files are only read, never moved."
        if panel.runModal() == .OK { panel.urls.forEach(library.addFolder) }
    }
}
