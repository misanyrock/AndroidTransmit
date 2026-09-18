import Foundation
import Observation

@MainActor @Observable
final class TransferQueue {
    private(set) var jobs: [TransferJob] = []
    private(set) var activeID: UUID?
    private(set) var connectedDeviceID: String?
    @ObservationIgnored private let engine: TransferEngine
    @ObservationIgnored private var control: TransferControl?
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored var onIdle: (() -> Void)?
    var isBusy: Bool { activeID != nil || jobs.contains { $0.state == .waiting } }
    var activeCount: Int { jobs.filter { !$0.state.isTerminal }.count }

    init(service: any MTPService) { engine = TransferEngine(service: service) }

    func setDevice(_ id: String?) {
        connectedDeviceID = id
        if id == nil {
            control?.cancel()
            for index in jobs.indices where !jobs[index].state.isTerminal {
                jobs[index].state = .failed
                jobs[index].detail = "设备已断开。重新连接后可重试；已完成的文件会保留。"
            }
        }
    }

    func enqueue(_ additions: [TransferJob]) {
        jobs.append(contentsOf: additions)
        startWorker()
    }

    func cancel(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), !jobs[index].state.isTerminal else { return }
        if activeID == id { control?.cancel(); jobs[index].detail = "正在取消，等待设备结束当前操作…" }
        else { jobs[index].state = .cancelled; jobs[index].detail = "尚未开始传输" }
    }

    func retry(_ id: UUID) {
        guard let old = jobs.first(where: { $0.id == id }), old.state.isTerminal, old.deviceID == connectedDeviceID else { return }
        enqueue([TransferJob(deviceID: old.deviceID, storageID: old.storageID, source: old.source, policy: old.policy, name: old.name, remotePath: old.remotePath)])
    }

    func clearFinished() { jobs.removeAll { $0.state.isTerminal && $0.id != activeID } }

    private func startWorker() {
        guard worker == nil else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            while let index = jobs.firstIndex(where: { $0.state == .waiting }) {
                let job = jobs[index]
                guard connectedDeviceID == job.deviceID else {
                    jobs[index].state = .failed; jobs[index].detail = "请连接此任务对应的设备。"; continue
                }
                let token = TransferControl()
                control = token; activeID = job.id
                jobs[index].state = .preparing
                let start = Date()
                do {
                    let detail = try await engine.run(job, control: token) { [weak self] done, total, state, detail in
                        await self?.update(job.id, done: done, total: total, state: state, detail: detail, start: start)
                    }
                    finish(job.id, state: .completed, detail: detail)
                } catch {
                    finish(job.id, state: token.isCancelled ? .cancelled : .failed,
                           detail: error is CancellationError ? "已取消传输" : error.localizedDescription)
                }
                activeID = nil; control = nil
            }
            worker = nil
            onIdle?()
        }
    }

    private func update(_ id: UUID, done: UInt64, total: UInt64, state: TransferState, detail: String, start: Date) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), !jobs[index].state.isTerminal else { return }
        jobs[index].state = state
        jobs[index].completedBytes = done
        jobs[index].totalBytes = total
        jobs[index].bytesPerSecond = Double(done) / max(Date().timeIntervalSince(start), 0.1)
        if control?.isCancelled != true { jobs[index].detail = detail }
    }

    private func finish(_ id: UUID, state: TransferState, detail: String) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), !jobs[index].state.isTerminal else { return }
        jobs[index].state = state; jobs[index].detail = detail
    }
}
