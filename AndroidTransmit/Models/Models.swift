import Foundation

struct Device: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let bus: UInt32
    let address: UInt8
    var registryID: UInt64? = nil
}

struct Storage: Identifiable, Hashable, Sendable {
    let id: UInt32
    let name: String
    let capacity: UInt64
    let free: UInt64
}

struct RemoteEntry: Identifiable, Hashable, Sendable {
    let id: UInt32
    let storageID: UInt32
    let parentID: UInt32
    let name: String
    let size: UInt64
    let modified: Date
    let isFolder: Bool
    var kind: String { isFolder ? "文件夹" : (URL(fileURLWithPath: name).pathExtension.uppercased().isEmpty ? "文件" : URL(fileURLWithPath: name).pathExtension.uppercased()) }
}

struct FolderLocation: Hashable, Sendable {
    let id: UInt32
    let name: String
}

enum ConflictPolicy: String, CaseIterable, Identifiable, Sendable {
    case keepBoth = "保留两者", skip = "跳过"
    var id: Self { self }
}

enum TransferState: String, Sendable {
    case waiting = "等待", preparing = "准备中", running = "进行中", completed = "完成", failed = "失败", cancelled = "已取消"
    var isTerminal: Bool { self == .completed || self == .failed || self == .cancelled }
}

enum TransferSource: Sendable {
    case upload(URL, parentID: UInt32)
    case download(RemoteEntry, destination: URL)
}

struct TransferJob: Identifiable, Sendable {
    let id = UUID()
    let deviceID: String
    let storageID: UInt32
    let source: TransferSource
    let policy: ConflictPolicy
    let name: String
    var remotePath: [String] = []
    var state: TransferState = .waiting
    var completedBytes: UInt64 = 0
    var totalBytes: UInt64 = 0
    var bytesPerSecond: Double = 0
    var detail = ""
    var isUpload: Bool { if case .upload = source { return true }; return false }
}

struct AppFailure: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

enum FileRules {
    static func validateName(_ name: String) throws {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0"), !name.contains(":") else {
            throw AppFailure("无效文件名：\(name)。名称不能为空，也不能包含 /、: 或路径跳转。")
        }
    }

    static func availableName(_ name: String, existing: Set<String>, policy: ConflictPolicy, isFolder: Bool) throws -> String? {
        try validateName(name)
        guard existing.contains(name) else { return name }
        guard policy == .keepBoth else { return nil }
        let url = URL(fileURLWithPath: name)
        let ext = isFolder ? "" : url.pathExtension
        let stem = ext.isEmpty ? name : String(name.dropLast(ext.count + 1))
        var number = 2
        while true {
            let candidate = "\(stem) (\(number))" + (ext.isEmpty ? "" : ".\(ext)")
            if !existing.contains(candidate) { return candidate }
            number += 1
        }
    }
}
