import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var store: BrowserStore
    @State private var sortOrder = [KeyPathComparator(\RemoteEntry.name)]
    @State private var queueVisible = true
    @State private var nameSheet: NameAction?
    @State private var confirmingDelete = false
    @State private var dropTargeted = false

    private var visibleEntries: [RemoteEntry] {
        store.entries.filter { store.search.isEmpty || $0.name.localizedStandardContains(store.search) }
            .sorted(using: sortOrder)
            .sorted { $0.isFolder && !$1.isFolder }
    }

    var body: some View {
        NavigationSplitView {
            DeviceSidebar(store: store)
                .navigationSplitViewColumnWidth(min: 195, ideal: 225, max: 300)
        } detail: {
            VStack(spacing: 0) {
                if store.connected != nil {
                    pathBar
                    Divider()
                    fileContent
                    Divider()
                    statusBar
                } else {
                    ConnectionPlaceholder(isScanning: store.isScanning || store.isLoading) { Task { await store.scan() } }
                }
                if !store.transfers.jobs.isEmpty && queueVisible {
                    Divider()
                    TransferQueueView(queue: store.transfers)
                        .frame(height: 200)
                }
            }
            .navigationTitle(store.connected?.name ?? "AndroidTransmit")
            .toolbar { toolbar }
            .searchable(text: $store.search, prompt: "筛选当前文件夹")
        }
        .task { await store.start() }
        .alert("操作未完成", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("好", role: .cancel) { store.error = nil }
        } message: { Text(store.error ?? "") }
        .alert("删除 \(store.selectedEntries.count) 个项目？", isPresented: $confirmingDelete) {
            Button("取消", role: .cancel) {}
            Button("永久删除", role: .destructive) { Task { await store.deleteSelection() } }
        } message: { Text("这些文件及文件夹内容将从手机中永久删除，不会进入 Mac 废纸篓。") }
        .sheet(item: $nameSheet) { action in
            NameSheet(title: action.entry == nil ? "新建文件夹" : "重命名", initialName: action.entry?.name ?? "新建文件夹") { name in
                Task {
                    if let entry = action.entry { await store.rename(entry, to: name) }
                    else { await store.createFolder(name) }
                }
            }
        }
    }

    private var pathBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                Button { Task { await store.navigate(to: 0) } } label: {
                    Label(store.selectedStorage?.name ?? "存储空间", systemImage: "internaldrive")
                }
                ForEach(Array(store.path.enumerated()), id: \.offset) { index, location in
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    Button(location.name) { Task { await store.navigate(to: index + 1) } }
                }
            }
            .buttonStyle(.plain)
            .disabled(!store.canOperate)
            .padding(.horizontal, 18).padding(.vertical, 12)
        }
    }

    private var fileContent: some View {
        Table(visibleEntries, selection: $store.selection, sortOrder: $sortOrder) {
            TableColumn("名称", value: \.name) { entry in
                HStack(spacing: 9) {
                    Image(systemName: entry.isFolder ? "folder.fill" : "doc")
                        .foregroundStyle(entry.isFolder ? Color.accentColor : Color.secondary)
                    Text(entry.name).lineLimit(1)
                }
            }.width(min: 180, ideal: 340)
            TableColumn("大小", value: \.size) { entry in
                Text(entry.isFolder ? "—" : ByteCountFormatter.string(fromByteCount: Int64(clamping: entry.size), countStyle: .file))
                    .foregroundStyle(.secondary).monospacedDigit()
            }.width(min: 80, ideal: 90, max: 120)
            TableColumn("类型", value: \.kind) { entry in Text(entry.kind).foregroundStyle(.secondary) }
                .width(min: 60, ideal: 80, max: 130)
            TableColumn("修改时间", value: \.modified) { entry in
                Text(entry.modified.timeIntervalSince1970 > 0 ? entry.modified.formatted(date: .abbreviated, time: .shortened) : "—")
                    .foregroundStyle(.secondary)
            }.width(min: 130, ideal: 160, max: 200)
        }
        .onDeleteCommand { if store.canOperate && !store.selection.isEmpty { confirmingDelete = true } }
        .contextMenu(forSelectionType: UInt32.self) { ids in
            let selected = store.entries.filter { ids.contains($0.id) }
            if let first = selected.first, selected.count == 1 {
                if first.isFolder { Button("打开") { Task { await store.enter(first) } }.disabled(!store.canOperate) }
                Button("重命名…") { nameSheet = NameAction(entry: first) }.disabled(!store.canOperate)
            }
            Button("下载到 Mac…") { store.selection = ids; chooseDownload() }.disabled(ids.isEmpty || !store.canOperate)
            Divider()
            Button("删除…", role: .destructive) { store.selection = ids; confirmingDelete = true }.disabled(ids.isEmpty || !store.canOperate)
        } primaryAction: { ids in
            if ids.count == 1, let entry = store.entries.first(where: { ids.contains($0.id) }), entry.isFolder {
                Task { await store.enter(entry) }
            }
        }
        .overlay {
            if store.isLoading {
                ProgressView("正在读取手机…").padding(22).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            } else if visibleEntries.isEmpty {
                ContentUnavailableView(store.search.isEmpty ? "文件夹为空" : "没有匹配的文件", systemImage: store.search.isEmpty ? "folder" : "magnifyingglass", description: Text(store.search.isEmpty ? "点击上传，或将文件从 Finder 拖到这里。" : "尝试其他文件名。"))
                    .allowsHitTesting(false)
            }
        }
        .overlay { if dropTargeted { RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 3).padding(6).allowsHitTesting(false) } }
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
            guard store.canOperate else { return false }
            Task {
                var urls: [URL] = []
                for provider in providers {
                    if let url = await droppedURL(provider) { urls.append(url) }
                }
                store.upload(urls)
            }
            return true
        }
    }

    private var statusBar: some View {
        HStack {
            Text(store.selection.isEmpty ? "\(visibleEntries.count) 个项目" : "已选择 \(store.selection.count) 个项目")
            Spacer()
            if let storage = store.selectedStorage {
                Text("可用 " + ByteCountFormatter.string(fromByteCount: Int64(clamping: storage.free), countStyle: .file))
            }
        }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 18).padding(.vertical, 9)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { Task { await store.navigate(to: max(store.path.count - 1, 0)) } } label: { Image(systemName: "chevron.left") }
                .help("返回上一级").disabled(store.path.isEmpty || !store.canOperate)
            Button { Task { if store.connected == nil { await store.scan() } else { await store.reload() } } } label: { Image(systemName: "arrow.clockwise") }
                .help("刷新").disabled(store.isLoading || store.isScanning || store.transfers.isBusy)
        }
        ToolbarItemGroup {
            Button { chooseUpload() } label: { Label("上传", systemImage: "square.and.arrow.up") }.disabled(!store.canOperate).keyboardShortcut("u", modifiers: [.command, .shift])
            Button { chooseDownload() } label: { Label("下载", systemImage: "square.and.arrow.down") }.disabled(!store.canOperate || store.selection.isEmpty).keyboardShortcut("d", modifiers: [.command, .shift])
            Button { nameSheet = NameAction(entry: nil) } label: { Label("新建文件夹", systemImage: "folder.badge.plus") }.disabled(!store.canOperate).keyboardShortcut("n", modifiers: [.command, .shift])
            Menu {
                Picker("同名文件", selection: $store.conflictPolicy) {
                    ForEach(ConflictPolicy.allCases) { Text($0.rawValue).tag($0) }
                }
                Divider()
                Button("重命名…") { if let entry = store.selectedEntries.first { nameSheet = NameAction(entry: entry) } }
                    .disabled(store.selection.count != 1 || !store.canOperate)
                Button("删除…", role: .destructive) { confirmingDelete = true }.disabled(store.selection.isEmpty || !store.canOperate)
            } label: { Label("更多", systemImage: "ellipsis.circle") }
            Button { queueVisible.toggle() } label: { Label("传输队列", systemImage: "list.bullet.rectangle") }
                .help("传输队列（\(store.transfers.activeCount)）")
        }
    }

    private func chooseUpload() {
        let panel = NSOpenPanel()
        panel.title = "选择要上传到手机的项目"; panel.prompt = "上传"
        panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.allowsMultipleSelection = true
        panel.begin { response in
            if response == .OK { store.upload(panel.urls) }
        }
    }

    private func chooseDownload() {
        let panel = NSOpenPanel()
        panel.title = "选择下载文件夹"; panel.prompt = "下载到此文件夹"
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.begin { response in
            if response == .OK, let url = panel.url { store.download(to: url) }
        }
    }

    private func droppedURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                continuation.resume(returning: data.flatMap { URL(dataRepresentation: $0, relativeTo: nil) })
            }
        }
    }
}

private struct NameAction: Identifiable {
    let id = UUID()
    let entry: RemoteEntry?
}

private struct NameSheet: View {
    let title: String
    let initialName: String
    let submit: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var focused: Bool
    private var valid: Bool { (try? FileRules.validateName(name)) != nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.headline)
            TextField("名称", text: $name).textFieldStyle(.roundedBorder).focused($focused)
                .onSubmit { save() }
            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("确定") { save() }.keyboardShortcut(.defaultAction).disabled(!valid)
            }
        }.padding(24).frame(width: 360)
            .onAppear { name = initialName; focused = true }
    }
    private func save() { guard valid else { return }; submit(name); dismiss() }
}
