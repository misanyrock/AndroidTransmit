import Foundation
import Observation

@MainActor @Observable
final class BrowserStore {
    var devices: [Device] = []
    private(set) var connected: Device?
    var storages: [Storage] = []
    var storageID: UInt32?
    var entries: [RemoteEntry] = []
    var path: [FolderLocation] = []
    var selection: Set<UInt32> = []
    var search = ""
    var error: String?
    var isLoading = false
    var isScanning = false
    var conflictPolicy: ConflictPolicy = .keepBoth
    let transfers: TransferQueue
    @ObservationIgnored private let service: any MTPService
    @ObservationIgnored private var watcher: USBWatcher?
    @ObservationIgnored private var usbDebounce: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var loadVersion = 0
    var parentID: UInt32 { path.last?.id ?? UInt32.max }
    var selectedEntries: [RemoteEntry] { entries.filter { selection.contains($0.id) } }
    var canOperate: Bool { connected != nil && storageID != nil && !isLoading && !isScanning && !transfers.isBusy }
    var selectedStorage: Storage? { storages.first { $0.id == storageID } }

    init(service: any MTPService = NativeMTPService()) {
        self.service = service
        transfers = TransferQueue(service: service)
        transfers.onIdle = { [weak self] in
            guard let self, self.connected != nil else { return }
            Task { await self.reload() }
        }
    }

    func start() async {
        if watcher == nil {
            watcher = USBWatcher { [weak self] in
                Task { @MainActor in self?.usbChanged() }
            }
        }
        await scan()
    }

    func shutdown() async {
        watcher = nil
        usbDebounce?.cancel()
        transfers.onIdle = nil
        for job in transfers.jobs where !job.state.isTerminal { transfers.cancel(job.id) }
        while transfers.isBusy { try? await Task.sleep(for: .milliseconds(50)) }
        await service.disconnect()
    }

    private func usbChanged() {
        usbDebounce?.cancel()
        usbDebounce = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            // Device enumeration itself is serialized with MTP, so use the OS USB
            // inventory to interrupt a transfer immediately if its device vanished.
            if let connected, !Self.usbDevicePresent(connected) {
                generation += 1; loadVersion += 1; isLoading = false
                transfers.setDevice(nil)
                self.connected = nil; storages = []; storageID = nil; entries = []; path = []; selection = []
                error = "手机已断开，请重新连接后重试未完成的任务。"
                await service.disconnect()
            }
            await scan()
        }
    }

    private static func usbDevicePresent(_ device: Device) -> Bool {
        guard let registryID = device.registryID else { return true }
        return USBIdentity.isPresent(registryID: registryID)
    }

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        do {
            devices = try await service.discover()
            if let current = connected, !devices.contains(where: { $0.id == current.id }) {
                generation += 1; loadVersion += 1; isLoading = false; transfers.setDevice(nil)
                connected = nil; storages = []; storageID = nil; entries = []; path = []
                await service.disconnect()
            }
            if connected == nil, let first = devices.first { await connect(first) }
        } catch { self.error = error.localizedDescription }
    }

    func connect(_ device: Device) async {
        guard !transfers.isBusy else { return }
        generation += 1
        let version = generation
        isLoading = true
        connected = nil; storages = []; storageID = nil; entries = []; path = []; selection = []
        transfers.setDevice(nil)
        do {
            let result = try await service.connect(device)
            guard generation == version else { return }
            connected = device; storages = result; storageID = result.first?.id
            transfers.setDevice(device.id)
            error = nil
            isLoading = false
            await reload()
        } catch { if generation == version { self.error = error.localizedDescription; isLoading = false } }
    }

    func chooseStorage(_ id: UInt32) async {
        guard !transfers.isBusy else { return }
        storageID = id; path = []; selection = []; search = ""
        await reload()
    }

    func reload() async {
        guard let storageID, connected != nil, !transfers.isBusy else { return }
        loadVersion += 1
        let version = loadVersion
        let connectionVersion = generation
        let parent = parentID
        isLoading = true
        defer { if loadVersion == version { isLoading = false } }
        do {
            let result = try await service.list(storage: storageID, parent: parent)
            guard version == loadVersion, connectionVersion == generation else { return }
            entries = result
            selection.formIntersection(Set(result.map(\.id)))
        } catch { if version == loadVersion, connectionVersion == generation { self.error = error.localizedDescription } }
    }

    func enter(_ entry: RemoteEntry) async {
        guard entry.isFolder, canOperate else { return }
        path.append(FolderLocation(id: entry.id, name: entry.name)); selection = []; search = ""
        await reload()
    }

    func navigate(to count: Int) async {
        guard canOperate else { return }
        path = Array(path.prefix(count)); selection = []; search = ""
        await reload()
    }

    func upload(_ urls: [URL]) {
        guard canOperate, let connected, let storageID else { return }
        transfers.enqueue(urls.map { TransferJob(deviceID: connected.id, storageID: storageID, source: .upload($0, parentID: parentID), policy: conflictPolicy, name: $0.lastPathComponent, remotePath: path.map(\.name)) })
    }

    func download(to destination: URL) {
        guard canOperate, let connected, let storageID else { return }
        transfers.enqueue(selectedEntries.map { TransferJob(deviceID: connected.id, storageID: storageID, source: .download($0, destination: destination), policy: conflictPolicy, name: $0.name, remotePath: path.map(\.name)) })
    }

    func createFolder(_ name: String) async {
        guard canOperate, let storageID else { return }
        await mutate { _ = try await self.service.createFolder(name: name, storage: storageID, parent: self.parentID) }
    }

    func rename(_ entry: RemoteEntry, to name: String) async {
        guard canOperate else { return }
        await mutate { try await self.service.rename(entry, to: name) }
    }

    func deleteSelection() async {
        guard canOperate else { return }
        let selected = selectedEntries
        await mutate { for entry in selected { try await self.service.delete(entry) } }
    }

    private func mutate(_ operation: () async throws -> Void) async {
        isLoading = true
        do { try await operation() } catch { self.error = error.localizedDescription }
        isLoading = false
        await reload()
    }
}

import IOKit
