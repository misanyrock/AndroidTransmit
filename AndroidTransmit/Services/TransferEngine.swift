import Foundation

struct TransferTree: Sendable {
    let name: String
    let size: UInt64
    let isFolder: Bool
    let localURL: URL?
    let remote: RemoteEntry?
    let children: [TransferTree]
    var totalBytes: UInt64 { isFolder ? children.reduce(0) { $0 + $1.totalBytes } : size }
}

struct TransferEngine: Sendable {
    let service: any MTPService
    typealias Progress = @Sendable (UInt64, UInt64, TransferState, String) async -> Void

    private func localTree(_ url: URL, control: TransferControl) throws -> TransferTree {
        try control.checkCancellation()
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey, .fileSizeKey])
        guard values.isSymbolicLink != true else { throw AppFailure("已拒绝符号链接：\(url.lastPathComponent)。请移除链接后重试。") }
        guard values.isDirectory == true || values.isRegularFile == true else { throw AppFailure("不支持此文件类型：\(url.lastPathComponent)") }
        try FileRules.validateName(url.lastPathComponent)
        let isFolder = values.isDirectory == true
        let children = isFolder ? try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).sorted { $0.lastPathComponent < $1.lastPathComponent }.map { try localTree($0, control: control) } : []
        return TransferTree(name: url.lastPathComponent, size: UInt64(values.fileSize ?? 0), isFolder: isFolder, localURL: url, remote: nil, children: children)
    }

    private func remoteTree(_ entry: RemoteEntry, control: TransferControl, ancestors: Set<UInt32> = []) async throws -> TransferTree {
        try control.checkCancellation()
        try FileRules.validateName(entry.name)
        guard !ancestors.contains(entry.id) else { throw AppFailure("手机返回了循环目录，已停止传输。") }
        var children: [TransferTree] = []
        if entry.isFolder {
            var ancestors = ancestors; ancestors.insert(entry.id)
            for child in try await service.list(storage: entry.storageID, parent: entry.id) {
                children.append(try await remoteTree(child, control: control, ancestors: ancestors))
            }
        }
        return TransferTree(name: entry.name, size: entry.size, isFolder: entry.isFolder, localURL: nil, remote: entry, children: children)
    }

    func run(_ job: TransferJob, control: TransferControl, progress: @escaping Progress) async throws -> String {
        await progress(0, 0, .preparing, "正在准备文件清单…")
        let parent = try await resolveParent(storage: job.storageID, path: job.remotePath, control: control)
        let tree: TransferTree
        switch job.source {
        case .upload(let url, _): tree = try localTree(url, control: control)
        case .download(let entry, _):
            let matches = try await service.list(storage: job.storageID, parent: parent).filter { $0.name == entry.name && $0.isFolder == entry.isFolder }
            guard matches.count == 1, let current = matches.first else { throw AppFailure("源文件已移动、删除或名称不唯一：\(entry.name)。请重新选择文件。") }
            tree = try await remoteTree(current, control: control)
        }
        try control.checkCancellation()
        let total = tree.totalBytes
        await progress(0, total, .running, "")
        var completed: UInt64 = 0
        var skipped = 0
        switch job.source {
        case .upload:
            try await uploadTree(tree, parent: parent, storage: job.storageID, policy: job.policy, control: control, total: total, completed: &completed, skipped: &skipped, progress: progress)
        case .download(_, let destination):
            let values = try destination.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { throw AppFailure("请选择实际存在的下载文件夹。") }
            try await downloadTree(tree, destination: destination.resolvingSymlinksInPath(), policy: job.policy, control: control, total: total, completed: &completed, skipped: &skipped, progress: progress)
        }
        try control.checkCancellation()
        await progress(completed, total, .running, "")
        return skipped == 0 ? "传输完成" : "处理完成，跳过 \(skipped) 个同名项目"
    }

    private func resolveParent(storage: UInt32, path: [String], control: TransferControl) async throws -> UInt32 {
        var parent = UInt32.max
        for component in path {
            try control.checkCancellation()
            try FileRules.validateName(component)
            let matches = try await service.list(storage: storage, parent: parent).filter { $0.name == component && $0.isFolder }
            guard matches.count == 1 else { throw AppFailure("原目录已移动、删除或名称不唯一：\(component)。请重新选择传输目录。") }
            parent = matches[0].id
        }
        return parent
    }

    private func transferFile(size: UInt64, completed: UInt64, total: UInt64, name: String, control: TransferControl,
                              progress: @escaping Progress, operation: () async throws -> Void) async throws {
        let poll = Task {
            // Native bridge resets counters when an actual file operation starts.
            // Initial delay avoids displaying the previous file's last sample.
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(150)) } catch { break }
                if Task.isCancelled { break }
                let (done, _) = control.progress
                await progress(completed + min(done, size), total, .running, name)
            }
        }
        do {
            try await operation()
            poll.cancel(); await poll.value
        } catch {
            poll.cancel(); await poll.value
            throw error
        }
        await progress(completed + size, total, .running, name)
    }

    private func uploadTree(_ tree: TransferTree, parent: UInt32, storage: UInt32, policy: ConflictPolicy, control: TransferControl,
                            total: UInt64, completed: inout UInt64, skipped: inout Int, progress: @escaping Progress) async throws {
        try control.checkCancellation()
        let existing = Set(try await service.list(storage: storage, parent: parent).map(\.name))
        guard let name = try FileRules.availableName(tree.name, existing: existing, policy: policy, isFolder: tree.isFolder) else {
            skipped += 1; completed += tree.totalBytes; return
        }
        if tree.isFolder {
            let folder = try await service.createFolder(name: name, storage: storage, parent: parent)
            // Keep completed children when a directory job is interrupted; report partial output.
            do {
                for child in tree.children {
                    try await uploadTree(child, parent: folder, storage: storage, policy: policy, control: control, total: total, completed: &completed, skipped: &skipped, progress: progress)
                }
            } catch {
                throw AppFailure("\(error.localizedDescription)\n已完成的文件保留在手机文件夹“\(name)”中，目录可能不完整。")
            }
        } else if let url = tree.localURL {
            try await transferFile(size: tree.size, completed: completed, total: total, name: name, control: control, progress: progress) {
                try await service.upload(url, name: name, storage: storage, parent: parent, control: control)
            }
            completed += tree.size
        }
    }

    private func downloadTree(_ tree: TransferTree, destination: URL, policy: ConflictPolicy, control: TransferControl,
                              total: UInt64, completed: inout UInt64, skipped: inout Int, progress: @escaping Progress) async throws {
        try control.checkCancellation()
        let existing = Set(try FileManager.default.contentsOfDirectory(atPath: destination.path))
        guard let name = try FileRules.availableName(tree.name, existing: existing, policy: policy, isFolder: tree.isFolder) else {
            skipped += 1; completed += tree.totalBytes; return
        }
        let target = destination.appendingPathComponent(name, isDirectory: tree.isFolder)
        if tree.isFolder {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
            do {
                for child in tree.children {
                    try await downloadTree(child, destination: target, policy: policy, control: control, total: total, completed: &completed, skipped: &skipped, progress: progress)
                }
            } catch {
                throw AppFailure("\(error.localizedDescription)\n已完成的文件保留在“\(target.path)”中，目录可能不完整。")
            }
        } else if let entry = tree.remote {
            let temporary = destination.appendingPathComponent(".androidtransmit-\(UUID().uuidString).partial")
            defer { try? FileManager.default.removeItem(at: temporary) }
            try await transferFile(size: tree.size, completed: completed, total: total, name: name, control: control, progress: progress) {
                try await service.download(entry, to: temporary, control: control)
            }
            try control.checkCancellation()
            // RENAME_EXCL is atomic and never replaces an existing destination.
            guard renamex_np(temporary.path, target.path, UInt32(RENAME_EXCL)) == 0 else {
                throw AppFailure("无法保存“\(name)”：\(String(cString: strerror(errno)))。原有文件未被覆盖。")
            }
            completed += tree.size
        }
    }
}
