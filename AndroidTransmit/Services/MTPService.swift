import Foundation

protocol MTPService: Sendable {
    func discover() async throws -> [Device]
    func connect(_ device: Device) async throws -> [Storage]
    func disconnect() async
    func list(storage: UInt32, parent: UInt32) async throws -> [RemoteEntry]
    func createFolder(name: String, storage: UInt32, parent: UInt32) async throws -> UInt32
    func rename(_ entry: RemoteEntry, to name: String) async throws
    func delete(_ entry: RemoteEntry) async throws
    func upload(_ url: URL, name: String, storage: UInt32, parent: UInt32, control: TransferControl) async throws
    func download(_ entry: RemoteEntry, to url: URL, control: TransferControl) async throws
}

final class TransferControl: @unchecked Sendable {
    let pointer: OpaquePointer
    init() { pointer = ATControlCreate()! }
    deinit { ATControlDestroy(pointer) }
    func cancel() { ATControlCancel(pointer) }
    var isCancelled: Bool { ATControlIsCancelled(pointer) != 0 }
    var progress: (UInt64, UInt64) { (ATControlDone(pointer), ATControlTotal(pointer)) }
    func checkCancellation() throws { if isCancelled { throw CancellationError() } }
}
