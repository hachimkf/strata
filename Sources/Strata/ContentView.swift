import SwiftUI
import AppKit
import StrataCore

enum SidebarItem: Hashable {
    case all, week, review, loose, tidy
    case folder(URL)
    case collection(String)
    case project(String)

    /// A list view (as opposed to a client page or a single project).
    var isList: Bool {
        switch self {
        case .collection, .project: return false
        default: return true
        }
    }
}

enum SortOrder: String, CaseIterable, Identifiable {
    case recent = "Recent", versions = "Most versions", name = "A–Z"
    var id: String { rawValue }
}

struct ContentView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var quickFind: QuickFindState
    @AppStorage(Prefs.accentKey) private var accent = 0
    @ViewState private var selection: SidebarItem = .all
    /// The list view to return to from a client or project.
    @ViewState private var lastList: SidebarItem = .all
    @ViewState private var search = ""
    @ViewState private var sort: SortOrder = .recent

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $selection)
                .navigationSplitViewColumnWidth(min: 250, ideal: 290, max: 360)
        } detail: {
            detailRoot
                .overlay(alignment: .bottomTrailing) {
                    if selection.isList {
                        ExtendedFAB(title: "Find anything", symbol: "magnifyingglass", shortcut: "⌘K") {
                            withAnimation(Motion.standard) { quickFind.isOpen = true }
                        }
                        .padding(26)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
        }
        .overlay {
            if quickFind.isOpen {
                QuickFindView(navigate: { go($0) }, close: { withAnimation(Motion.standard) { quickFind.isOpen = false } })
            }
        }
        .overlay(alignment: .bottom) {
            if let message = library.toast {
                Toast(message: message)
                    .padding(.bottom, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .themed(Prefs.accent(accent))
        .searchable(text: $search, placement: .toolbar, prompt: "Search clients, projects and files")
        .onChange(of: selection) { if selection.isList { lastList = selection } }
        .onChange(of: quickFind.pending) {
            if let item = quickFind.pending { go(item); quickFind.pending = nil }
        }
        .onAppear {
            if let item = quickFind.pending { go(item); quickFind.pending = nil }
        }
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

    private func go(_ item: SidebarItem) { withAnimation(Motion.standard) { selection = item } }

    @ViewBuilder private var detailRoot: some View {
        switch selection {
        case .loose:
            LooseFilesView(files: filteredLoose)
        case .tidy:
            TidyView()
        case .collection(let id):
            if let collection = library.collection(id: id) {
                CollectionPage(collection: collection, backTitle: listTitle(lastList),
                               onBack: { go(lastList) }, openProject: { go(.project($0.id)) })
                    .id(id)
            } else {
                missing
            }
        case .project(let id):
            if let project = library.project(id: id) {
                let parent = library.collection(containing: id)
                ProjectDetailView(project: project, backTitle: parent?.name ?? listTitle(lastList)) {
                    go(parent.map { .collection($0.id) } ?? lastList)
                }
                .id(id)
            } else {
                missing
            }
        default:
            ProjectGridView(collections: filteredCollections, projects: filteredProjects, title: title, subtitle: subtitle,
                            hero: selection == .all && search.isEmpty && sort == .recent ? library.projects.first : nil,
                            sort: $sort,
                            open: { go(.project($0.id)) },
                            openCollection: { go(.collection($0.id)) })
        }
    }

    private var missing: some View {
        ContentUnavailableView("Not found", systemImage: "questionmark.folder",
                               description: Text("Its files may have been moved or deleted."))
    }

    private var query: String { search.trimmingCharacters(in: .whitespaces).lowercased() }

    /// Home shows clients, then projects that belong to no client. Other views list projects directly.
    private var filteredCollections: [Client] {
        guard selection == .all else { return [] }
        var list = library.collections
        if !query.isEmpty {
            list = list.filter { c in
                c.name.lowercased().contains(query) || c.projects.contains { $0.name.lowercased().contains(query) }
                    || c.singles.contains { $0.name.lowercased().contains(query) }
            }
        }
        switch sort {
        case .recent: return list
        case .versions: return list.sorted { $0.fileCount > $1.fileCount }
        case .name: return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private var filteredProjects: [ProjectGroup] {
        var list = selection == .all ? library.standalone : library.projects
        switch selection {
        case .week:
            let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
            list = list.filter { $0.lastModified >= cutoff }
        case .review:
            list = list.filter(\.needsReview)
        case .folder(let url):
            list = list.filter { $0.files.contains { $0.file.path.hasPrefix(url.path + "/") } }
        default: break
        }
        if !query.isEmpty {
            list = list.filter { p in p.name.lowercased().contains(query) || p.files.contains { $0.file.name.lowercased().contains(query) } }
        }
        switch sort {
        case .recent: return list
        case .versions: return list.sorted { $0.versions.count > $1.versions.count }
        case .name: return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private var filteredLoose: [CreativeFile] {
        query.isEmpty ? library.loose : library.loose.filter { $0.name.lowercased().contains(query) }
    }

    private var title: String { listTitle(selection) }

    private func listTitle(_ item: SidebarItem) -> String {
        switch item {
        case .all, .project, .collection: return "Your work"
        case .week: return "This week"
        case .review: return "Needs review"
        case .loose: return "Loose files"
        case .tidy: return "Tidy up"
        case .folder(let url): return url.lastPathComponent
        }
    }

    private var subtitle: String {
        switch selection {
        case .review: return "Crash-recovered files and exact duplicates to tidy up"
        case .week: return "Everything you saved in the last 7 days"
        case .folder: return "Projects with at least one file in this folder"
        default: return "\(library.collections.count) clients · \(library.projects.count) projects · every version in one place"
        }
    }
}

// MARK: - Sidebar

/// Native macOS source list: reliable clicks, ↑↓ to move, ←→ to fold clients, type to jump.
struct Sidebar: View {
    @EnvironmentObject var library: Library
    @Environment(\.palette) private var palette
    @Binding var selection: SidebarItem
    @ViewState private var filter = ""
    @ViewState private var expanded: Set<String> = []
    @ViewState private var renamingClient: Client?
    @ViewState private var renamingProject: ProjectGroup?
    @ViewState private var mergingClient: Client?
    @ViewState private var clientForProject: ProjectGroup?

    var body: some View {
        VStack(spacing: 0) {
            brand.padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 10)
            filterField.padding(.horizontal, 12).padding(.bottom, 6)
            ScrollViewReader { proxy in
                List(selection: listSelection) {
                    Section {
                        row(.all, "Your work", "square.stack.3d.up.fill", library.collections.count + library.standalone.count)
                        row(.week, "This week", "calendar", weekCount)
                        row(.review, "Needs review", "exclamationmark.triangle.fill", library.projects.filter(\.needsReview).count)
                        row(.loose, "Loose files", "doc.fill", library.loose.count)
                        row(.tidy, "Tidy up", "sparkles", tidyCount)
                    }

                    Section("Watching") {
                        ForEach(library.folders, id: \.self) { url in
                            row(.folder(url), url.lastPathComponent, "folder.fill", library.projectCount(in: url))
                                .contextMenu {
                                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                                    Button("Stop Watching", role: .destructive) { library.removeFolder(url) }
                                }
                        }
                        Button(action: addFolder) {
                            Label("Add folder…", systemImage: "plus")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(palette.primary)
                    }
                    Section("Clients") {
                        ForEach(clients) { client in
                            DisclosureGroup(isExpanded: expansion(client)) {
                                ForEach(projects(of: client)) { project in
                                    projectLabel(project, small: true)
                                        .tag(SidebarItem.project(project.id))
                                        .id(project.id)
                                        .contextMenu { projectMenu(project) }
                                        .dropDestination(for: URL.self) { urls, _ in drop(urls, onProject: project) }
                                }
                            } label: {
                                clientLabel(client)
                                    .tag(SidebarItem.collection(client.id))
                                    .id(client.id)
                                    .contextMenu {
                                        Button("Rename…") { renamingClient = client }
                                        Button("Merge into another client…") { mergingClient = client }
                                        Button("Show all in Finder") { FileActions.reveal(client.allFiles) }
                                        Divider()
                                        Button("Hide") { library.hide(client) }
                                    }
                                    .dropDestination(for: URL.self) { urls, _ in drop(urls, onClient: client) }
                            }
                        }
                    }

                    if !standalone.isEmpty {
                        Section("Other projects") {
                            ForEach(standalone) { project in
                                projectLabel(project, small: false)
                                    .tag(SidebarItem.project(project.id))
                                    .id(project.id)
                                    .contextMenu { projectMenu(project) }
                                    .dropDestination(for: URL.self) { urls, _ in drop(urls, onProject: project) }
                            }
                        }
                    }

                }
                .listStyle(.sidebar)
                .scrollFade(height: 28, tinted: false)
                .onChange(of: selection) { revealSelection(proxy) }
                .sheet(item: $renamingClient) { c in
                    NamePrompt(title: "Rename client", initial: c.name) { library.rename(c, to: $0) }
                }
                .sheet(item: $renamingProject) { p in
                    NamePrompt(title: "Rename project", initial: p.name) { library.rename(p, to: $0) }
                }
                .sheet(item: $mergingClient) { c in
                    PickerSheet(title: "Merge \(c.name) into…",
                                items: library.collections.filter { $0.id != c.id }.map {
                                    PickItem(id: $0.id, title: $0.name, subtitle: "\($0.projects.count) projects", file: $0.latest)
                                }) { item in
                        if let target = library.collection(id: item.id) { library.mergeClients(c, into: target) }
                    }
                }
                .sheet(item: $clientForProject) { p in
                    PickerSheet(title: "Move \(p.name) to client…",
                                items: library.collections.map {
                                    PickItem(id: $0.id, title: $0.name, subtitle: "\($0.projects.count) projects", file: $0.latest)
                                }) { item in
                        if let client = library.collection(id: item.id) { library.assign(p.first.file, to: client) }
                    }
                }
            }
            status
        }
    }

    /// The List only selects; anything not shown in the list (none today) is ignored.
    private var listSelection: Binding<SidebarItem?> {
        Binding(get: { selection }, set: { if let v = $0 { selection = v } })
    }

    /// Opening a project from the grid unfolds its client and scrolls to it, but only if it's off screen,
    /// so a click inside the sidebar never makes the list jump under the pointer.
    private func revealSelection(_ proxy: ScrollViewProxy) {
        guard case .project(let id) = selection, let parent = library.collection(containing: id) else { return }
        if !expanded.contains(parent.id) {
            expanded.insert(parent.id)
            DispatchQueue.main.async { proxy.scrollTo(id) }
        }
    }

    private var query: String { filter.trimmingCharacters(in: .whitespaces).lowercased() }

    private var clients: [Client] {
        guard !query.isEmpty else { return library.collections }
        return library.collections.filter { c in c.name.lowercased().contains(query) || c.projects.contains { $0.name.lowercased().contains(query) } }
    }

    private func projects(of c: Client) -> [ProjectGroup] {
        guard !query.isEmpty, !c.name.lowercased().contains(query) else { return c.projects }
        return c.projects.filter { $0.name.lowercased().contains(query) }
    }

    private var standalone: [ProjectGroup] {
        query.isEmpty ? library.standalone : library.standalone.filter { $0.name.lowercased().contains(query) }
    }

    /// While filtering, clients open by themselves so matching projects show.
    private func expansion(_ c: Client) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(c.id) || (!query.isEmpty && !c.name.lowercased().contains(query)) },
            set: { open in if open { expanded.insert(c.id) } else { expanded.remove(c.id) } }
        )
    }

    private var brand: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 34, height: 34)
                .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
            Text("Strata").font(.display(22)).foregroundStyle(palette.onSurface)
            Spacer()
        }
    }

    private var filterField: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease").font(.system(size: 12, weight: .semibold))
            TextField("Find a client or project", text: $filter)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
            if !filter.isEmpty {
                Button { filter = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
            }
        }
        .foregroundStyle(palette.onSurfaceVariant)
        .padding(.horizontal, 12).frame(height: 32)
        .background(Capsule().fill(palette.surfaceContainerHigh))
    }

    private func row(_ value: SidebarItem, _ title: String, _ symbol: String, _ count: Int) -> some View {
        Label {
            Text(title).font(.system(size: 13, weight: .medium))
        } icon: {
            Image(systemName: symbol).foregroundStyle(palette.primary)
        }
        .badge(count)
        .tag(value)
    }

    private func clientLabel(_ client: Client) -> some View {
        HStack(spacing: 8) {
            ZStack {
                if let latest = client.latest { Thumbnail(file: latest, side: 64) }
            }
            .frame(width: 22, height: 22)
            .clipShape(Cookie(lobes: 8, depth: 0.1))
            Text(client.name).font(.system(size: 13, weight: .semibold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Text("\(client.projects.count)")
                .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .help("\(client.name) · \(client.projects.count) projects · \(client.fileCount) files")
    }

    private func projectLabel(_ project: ProjectGroup, small: Bool) -> some View {
        HStack(spacing: 8) {
            Thumbnail(file: project.latest.file, side: 64)
                .frame(width: small ? 18 : 22, height: small ? 18 : 22)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            Text(project.name).font(.system(size: small ? 12.5 : 13, weight: .medium)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Text("\(project.versions.count)")
                .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .help("\(project.name) · \(project.versions.count) versions · latest \(Format.date(project.latest.file.modified))")
    }

    @ViewBuilder private func projectMenu(_ project: ProjectGroup) -> some View {
        Button("Open latest version") { FileActions.open(project.latest.file) }
        Button("Rename…") { renamingProject = project }
        Button("Move to client…") { clientForProject = project }
        if let client = library.collection(containing: project.id) {
            Button("Remove from \(client.name)") { library.removeFromClient(project) }
        }
        Divider()
        Button("Show all files in Finder") { FileActions.reveal(project.files.map(\.file)) }
    }

    /// Dropping files (from Strata or Finder) onto a project files them as versions of it.
    private func drop(_ urls: [URL], onProject project: ProjectGroup) -> Bool {
        let files = urls.compactMap { library.file(at: $0.path) }
        guard !files.isEmpty else {
            library.show("Only files inside your watched folders can be added")
            return false
        }
        files.forEach { library.move($0, toProjectOf: project) }
        return true
    }

    /// Dropping files onto a client puts their project into that client.
    private func drop(_ urls: [URL], onClient client: Client) -> Bool {
        let files = urls.compactMap { library.file(at: $0.path) }
        guard !files.isEmpty else {
            library.show("Only files inside your watched folders can be added")
            return false
        }
        files.forEach { library.assign($0, to: client) }
        return true
    }

    private var tidyCount: Int {
        library.projects.reduce(0) { n, p in
            n + p.duplicateCount + p.versions.filter { v in
                v.isRecovered && v.id != p.latest.id && p.versions.contains { $0.file.modified > v.file.modified && !$0.isRecovered }
            }.count
        }
    }

    private var weekCount: Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        return library.projects.filter { $0.lastModified >= cutoff }.count
    }

    private var status: some View {
        HStack(spacing: 8) {
            if library.isScanning {
                ProgressView().controlSize(.small)
                Text("Reading folders…")
            } else {
                Circle().fill(palette.primary).frame(width: 7, height: 7)
                Text("\(library.fileCount.formatted()) files · watching")
            }
            Spacer()
            SettingsLink {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(palette.surfaceContainerHigh, in: Circle())
                    .foregroundStyle(palette.onSurfaceVariant)
                    .contentShape(Circle())
            }
            .buttonStyle(PressScale())
            .help("Settings (⌘,)")
        }
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(palette.onSurfaceVariant)
        .padding(.leading, 18).padding(.trailing, 12).padding(.vertical, 8)
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Watch"
        panel.message = "Choose folders Strata should watch. Strata reads them; it never moves or edits your files on its own."
        if panel.runModal() == .OK { panel.urls.forEach(library.addFolder) }
    }
}

/// Expressive press feedback: squish on press, spring back.
struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Motion.fast, value: configuration.isPressed)
    }
}
