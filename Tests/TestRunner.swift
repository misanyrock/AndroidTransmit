import Foundation
import CryptoKit

actor FakeMTPService: MTPService {
    var entries: [UInt32: [RemoteEntry]] = [:]
    var data: [UInt32: Data] = [:]
    var uploads: [String] = []
    var nextID: UInt32 = 100
    var delay: Duration = .zero
    var shouldFail = false
    var active = 0
    var maximumActive = 0
    func configure(delay: Duration = .zero, fail: Bool = false) { self.delay = delay; shouldFail = fail }
    func seed(_ entry: RemoteEntry, payload: Data = Data()) { entries[entry.parentID, default: []].append(entry); data[entry.id] = payload }
    func snapshot() -> ([String], Int) { (uploads, maximumActive) }
    func discover() async throws -> [Device] { [] }
    func connect(_ device: Device) async throws -> [Storage] { [] }
    func disconnect() async {}
    func list(storage: UInt32, parent: UInt32) async throws -> [RemoteEntry] { entries[parent] ?? [] }
    func createFolder(name: String, storage: UInt32, parent: UInt32) async throws -> UInt32 {
        nextID += 1
        let entry = RemoteEntry(id: nextID, storageID: storage, parentID: parent, name: name, size: 0, modified: Date(), isFolder: true)
        entries[parent, default: []].append(entry)
        return nextID
    }
    func rename(_ entry: RemoteEntry, to name: String) async throws {}
    func delete(_ entry: RemoteEntry) async throws {}
    func upload(_ url: URL, name: String, storage: UInt32, parent: UInt32, control: TransferControl) async throws {
        active += 1; maximumActive = max(active, maximumActive)
        defer { active -= 1 }
        try await Task.sleep(for: delay)
        try control.checkCancellation()
        if shouldFail { throw AppFailure("模拟空间不足") }
        uploads.append(name)
        nextID += 1
        let payload = try Data(contentsOf: url)
        entries[parent, default: []].append(RemoteEntry(id: nextID, storageID: storage, parentID: parent, name: name, size: UInt64(payload.count), modified: Date(), isFolder: false))
    }
    func download(_ entry: RemoteEntry, to url: URL, control: TransferControl) async throws {
        try await Task.sleep(for: delay)
        try control.checkCancellation()
        try (data[entry.id] ?? Data()).write(to: url, options: .withoutOverwriting)
        if shouldFail { throw AppFailure("模拟设备断开") }
    }
}

@main struct TestRunner {
    static func expect(_ condition: Bool, _ message: String) throws { if !condition { throw AppFailure("测试失败：\(message)") } }
    static func entry(_ name: String, id: UInt32 = 1, parent: UInt32 = .max, size: UInt64 = 3, folder: Bool = false) -> RemoteEntry {
        RemoteEntry(id: id, storageID: 1, parentID: parent, name: name, size: size, modified: Date(), isFolder: folder)
    }
    static func uploadJob(_ url: URL) -> TransferJob {
        TransferJob(deviceID: "test", storageID: 1, source: .upload(url, parentID: .max), policy: .keepBoth, name: url.lastPathComponent)
    }
    @MainActor static func waitForIdle(_ queue: TransferQueue) async throws {
        for _ in 0..<500 {
            if !queue.isBusy { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw AppFailure("队列未在 5 秒内结束")
    }
    @MainActor static func main() async {
        setbuf(stdout, nil)
        do {
            if CommandLine.arguments.contains("--probe") { try await probe(); return }
            if CommandLine.arguments.contains("--device-smoke") { try await deviceSmoke(); return }
            try await runTests()
            print("PASS: all 12 test groups")
        } catch { print(error.localizedDescription); exit(1) }
    }
    @MainActor static func runTests() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("AndroidTransmit-tests-\(UUID())")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let local = root.appendingPathComponent("中文 file.txt")
        try Data("abc".utf8).write(to: local)
        let quiet: TransferEngine.Progress = { _, _, _, _ in }

        try expect(try FileRules.availableName("file.txt", existing: ["file.txt", "file (2).txt"], policy: .keepBoth, isFolder: false) == "file (3).txt", "同名文件编号")
        try expect(try FileRules.availableName("a.b", existing: ["a.b"], policy: .keepBoth, isFolder: true) == "a.b (2)", "目录名不拆扩展名")
        try expect(try FileRules.availableName("a", existing: ["a"], policy: .skip, isFolder: false) == nil, "跳过同名")
        print("PASS: conflict policies")
        for name in ["", ".", "..", "../escape", "/absolute", "a\0b", "a:b"] {
            do { try FileRules.validateName(name); throw AppFailure("应拒绝危险名称") }
            catch let failure as AppFailure { try expect(!failure.message.contains("应拒绝"), "拒绝 \(name)") }
        }
        print("PASS: path validation")

        let service = FakeMTPService()
        let engine = TransferEngine(service: service)
        let folder = root.appendingPathComponent("目录")
        try fm.createDirectory(at: folder.appendingPathComponent("空目录"), withIntermediateDirectories: true)
        try Data().write(to: folder.appendingPathComponent("零字节"))
        try Data("xyz".utf8).write(to: folder.appendingPathComponent("空格 文件"))
        _ = try await engine.run(uploadJob(folder), control: TransferControl(), progress: quiet)
        let result = await service.snapshot()
        try expect(Set(result.0) == ["零字节", "空格 文件"], "递归上传含空文件")
        print("PASS: recursive upload and empty files")

        let symbolic = root.appendingPathComponent("链接")
        try fm.createSymbolicLink(at: symbolic, withDestinationURL: local)
        do { _ = try await engine.run(uploadJob(symbolic), control: TransferControl(), progress: quiet); throw AppFailure("未拒绝链接") }
        catch let error as AppFailure { try expect(error.message.contains("符号链接"), "不跟随符号链接") }
        print("PASS: symlink refusal")

        let downloaded = root.appendingPathComponent("downloads")
        try fm.createDirectory(at: downloaded, withIntermediateDirectories: true)
        let remoteFolder = entry("照片", id: 10, size: 0, folder: true)
        await service.seed(remoteFolder)
        await service.seed(entry("中文.txt", id: 11, parent: 10), payload: Data("abc".utf8))
        let downloadJob = TransferJob(deviceID: "test", storageID: 1, source: .download(remoteFolder, destination: downloaded), policy: .keepBoth, name: "照片")
        _ = try await engine.run(downloadJob, control: TransferControl(), progress: quiet)
        try expect(try Data(contentsOf: downloaded.appendingPathComponent("照片/中文.txt")) == Data("abc".utf8), "递归下载内容")
        _ = try await engine.run(downloadJob, control: TransferControl(), progress: quiet)
        try expect(fm.fileExists(atPath: downloaded.appendingPathComponent("照片 (2)/中文.txt").path), "下载保留两者")
        print("PASS: recursive download and conflict preservation")

        let remoteFile = entry("broken.txt", id: 12)
        await service.seed(remoteFile, payload: Data("abc".utf8))
        await service.configure(fail: true)
        let failedJob = TransferJob(deviceID: "test", storageID: 1, source: .download(remoteFile, destination: downloaded), policy: .keepBoth, name: remoteFile.name)
        do { _ = try await engine.run(failedJob, control: TransferControl(), progress: quiet); throw AppFailure("预期失败") }
        catch { try expect(!fm.fileExists(atPath: downloaded.appendingPathComponent(remoteFile.name).path), "失败下载没有正式文件") }
        try expect(try !fm.contentsOfDirectory(atPath: downloaded.path).contains { $0.hasSuffix(".partial") }, "清理临时文件")
        print("PASS: failed download cleanup")

        let cancelled = TransferControl(); cancelled.cancel()
        do { _ = try await engine.run(uploadJob(local), control: cancelled, progress: quiet); throw AppFailure("预期取消") }
        catch is CancellationError {}
        print("PASS: cancellation before planning")

        let queueService = FakeMTPService()
        await queueService.configure(delay: .milliseconds(40))
        let queue = TransferQueue(service: queueService)
        queue.setDevice("test")
        queue.enqueue([uploadJob(local), uploadJob(local)])
        try await waitForIdle(queue)
        try expect(queue.jobs.allSatisfy { $0.state == .completed }, "队列成功状态")
        try expect(await queueService.snapshot().1 == 1, "一次只传一个文件")
        print("PASS: serialized queue")

        await queueService.configure(delay: .milliseconds(150))
        queue.enqueue([uploadJob(local), uploadJob(local)])
        let activeID = queue.jobs[2].id
        let waitingID = queue.jobs[3].id
        try await Task.sleep(for: .milliseconds(20))
        queue.cancel(activeID); queue.cancel(waitingID)
        try await waitForIdle(queue)
        try expect(queue.jobs[2].state == .cancelled && queue.jobs[3].state == .cancelled, "活动和等待任务取消")
        print("PASS: active and waiting cancellation")

        await queueService.configure(fail: true)
        queue.enqueue([uploadJob(local)])
        try await waitForIdle(queue)
        try expect(queue.jobs.last?.state == .failed, "错误不能报成功")
        let failedID = queue.jobs.last!.id
        await queueService.configure()
        queue.retry(failedID)
        try await waitForIdle(queue)
        try expect(queue.jobs.last?.state == .completed, "手动重试")
        print("PASS: failure and retry")

        await queueService.configure(delay: .milliseconds(150))
        queue.enqueue([uploadJob(local), uploadJob(local)])
        try await Task.sleep(for: .milliseconds(20))
        queue.setDevice(nil)
        try await waitForIdle(queue)
        try expect(queue.jobs.suffix(2).allSatisfy { $0.state == .failed }, "断线状态不被取消回调覆盖")
        print("PASS: disconnected queue")

        let reconnected = FakeMTPService()
        await reconnected.seed(entry("相册", id: 200, size: 0, folder: true))
        await reconnected.seed(entry("photo", id: 201, parent: 200), payload: Data("new".utf8))
        var stale = TransferJob(deviceID: "test", storageID: 1, source: .download(entry("photo", id: 9, parent: 8), destination: downloaded), policy: .keepBoth, name: "photo")
        stale.remotePath = ["相册"]
        _ = try await TransferEngine(service: reconnected).run(stale, control: TransferControl(), progress: quiet)
        try expect(try Data(contentsOf: downloaded.appendingPathComponent("photo")) == Data("new".utf8), "重连重新解析文件编号")
        print("PASS: reconnect resolves object IDs")
    }

    static func probe() async throws {
        let service = NativeMTPService()
        let devices = try await service.discover()
        print("MTP devices: \(devices.count)")
        for device in devices {
            print("Device: \(device.name)")
            let storages = try await service.connect(device)
            for storage in storages {
                let files = try await service.list(storage: storage.id, parent: .max)
                print("Storage: \(storage.name), free: \(storage.free), root entries: \(files.count)")
            }
            await service.disconnect()
        }
    }

    static func deviceSmoke() async throws {
        let service = NativeMTPService()
        guard let device = try await service.discover().first else { throw AppFailure("没有连接 MTP 手机，真机测试未执行。") }
        guard let storage = try await service.connect(device).first else { throw AppFailure("没有可用存储。") }
        let name = "AndroidTransmit-Test-\(UUID().uuidString)"
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(name)
        try fm.createDirectory(at: root.appendingPathComponent("往返/中文 空目录"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let payload = Data((0..<(8 * 1024 * 1024)).map { UInt8($0 % 251) })
        try payload.write(to: root.appendingPathComponent("往返/中文 file.bin"))
        try Data().write(to: root.appendingPathComponent("往返/空文件"))
        let largeURL = root.appendingPathComponent("往返/大文件.bin")
        fm.createFile(atPath: largeURL.path, contents: nil)
        let largeHandle = try FileHandle(forWritingTo: largeURL)
        let chunk = Data(repeating: 0xA7, count: 1024 * 1024)
        for _ in 0..<256 { try largeHandle.write(contentsOf: chunk) }
        try largeHandle.close()
        let testFolderID = try await service.createFolder(name: name, storage: storage.id, parent: .max)
        let testFolder = RemoteEntry(id: testFolderID, storageID: storage.id, parentID: .max, name: name, size: 0, modified: Date(), isFolder: true)
        do {
            let engine = TransferEngine(service: service)
            let upload = TransferJob(deviceID: device.id, storageID: storage.id, source: .upload(root.appendingPathComponent("往返"), parentID: testFolderID), policy: .keepBoth, name: "往返", remotePath: [name])
            print("Uploading 256 MiB + fixtures…")
            _ = try await engine.run(upload, control: TransferControl(), progress: { _, _, _, _ in })
            guard let folder = try await service.list(storage: storage.id, parent: testFolderID).first(where: { $0.name == "往返" }) else { throw AppFailure("上传目录未找到") }
            try await service.rename(folder, to: "已重命名")
            guard let renamed = try await service.list(storage: storage.id, parent: testFolderID).first(where: { $0.name == "已重命名" }) else { throw AppFailure("重命名未生效") }
            let download = TransferJob(deviceID: device.id, storageID: storage.id, source: .download(renamed, destination: root), policy: .keepBoth, name: renamed.name, remotePath: [name])
            print("Downloading 256 MiB + fixtures…")
            _ = try await engine.run(download, control: TransferControl(), progress: { _, _, _, _ in })
            let actual = try Data(contentsOf: root.appendingPathComponent("已重命名/中文 file.bin"))
            try expect(SHA256.hash(data: actual) == SHA256.hash(data: payload), "真机 SHA-256 往返校验")
            try expect(fm.fileExists(atPath: root.appendingPathComponent("已重命名/中文 空目录").path), "真机空目录")
            let largeDownloaded = try Data(contentsOf: root.appendingPathComponent("已重命名/大文件.bin"), options: .mappedIfSafe)
            let largeOriginal = try Data(contentsOf: largeURL, options: .mappedIfSafe)
            try expect(SHA256.hash(data: largeDownloaded) == SHA256.hash(data: largeOriginal), "256 MiB 往返校验")
            print("PASS: 256 MiB SHA-256 roundtrip")
            let cancellation = TransferControl()
            let cancelTask = Task {
                while !Task.isCancelled {
                    if cancellation.progress.0 >= 1_048_576 { cancellation.cancel(); return }
                    try? await Task.sleep(for: .milliseconds(5))
                }
            }
            print("Testing upload cancellation…")
            var didCancel = false
            do { try await service.upload(largeURL, name: "取消测试.bin", storage: storage.id, parent: testFolderID, control: cancellation) }
            catch { didCancel = cancellation.isCancelled; print("Cancellation: \(error.localizedDescription)") }
            cancelTask.cancel(); await cancelTask.value
            try expect(didCancel, "真实上传取消")
            print("PASS: native upload cancellation")
            guard let largeRemote = try await service.list(storage: storage.id, parent: renamed.id).first(where: { $0.name == "大文件.bin" }) else { throw AppFailure("找不到大文件") }
            let cancelDestination = root.appendingPathComponent("取消下载")
            try fm.createDirectory(at: cancelDestination, withIntermediateDirectories: false)
            let downloadCancellation = TransferControl()
            let cancelDownloadTask = Task {
                while !Task.isCancelled {
                    if downloadCancellation.progress.0 >= 1_048_576 { downloadCancellation.cancel(); return }
                    try? await Task.sleep(for: .milliseconds(5))
                }
            }
            print("Testing download cancellation…")
            let cancellationJob = TransferJob(deviceID: device.id, storageID: storage.id, source: .download(largeRemote, destination: cancelDestination), policy: .keepBoth, name: largeRemote.name, remotePath: [name, "已重命名"])
            var downloadWasCancelled = false
            do { _ = try await engine.run(cancellationJob, control: downloadCancellation, progress: { _, _, _, _ in }) }
            catch { downloadWasCancelled = downloadCancellation.isCancelled }
            cancelDownloadTask.cancel(); await cancelDownloadTask.value
            try expect(downloadWasCancelled, "真实下载取消")
            try expect(try fm.contentsOfDirectory(atPath: cancelDestination.path).isEmpty, "取消下载清理临时文件")
            print("PASS: native download cancellation and cleanup")
            print("Cleaning test directory…")
            try await service.delete(testFolder)
            try expect(try await !service.list(storage: storage.id, parent: .max).contains(where: { $0.name == name }), "测试目录已删除")
            await service.disconnect()
            print("PASS: device roundtrip, SHA-256, Unicode, empty file/folder, rename, recursive delete")
        } catch {
            print("真机测试失败；测试目录为 \(name)，正在尝试清理。")
            do { try await service.delete(testFolder) } catch { print("未能清理测试目录：\(error.localizedDescription)") }
            await service.disconnect()
            throw error
        }
    }
}
