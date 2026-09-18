import SwiftUI

struct TransferQueueView: View {
    @Bindable var queue: TransferQueue
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("传输队列").font(.headline)
                Text("\(queue.activeCount) 项待完成").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("清除已结束") { queue.clearFinished() }.buttonStyle(.plain).font(.caption)
            }.padding(.horizontal, 18).padding(.vertical, 10)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(queue.jobs) { job in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: job.isUpload ? "arrow.up.circle" : "arrow.down.circle").font(.title3).foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(job.name).lineLimit(1)
                                    Spacer()
                                    Text(job.state.rawValue).font(.caption).foregroundStyle(job.state == .failed ? Color.red : Color.secondary)
                                }
                                if !job.state.isTerminal {
                                    if job.state == .preparing { ProgressView().progressViewStyle(.linear) }
                                    else { ProgressView(value: Double(job.completedBytes), total: Double(max(job.totalBytes, 1))) }
                                    Text("\(bytes(job.completedBytes)) / \(bytes(job.totalBytes)) · \(bytes(UInt64(max(0, job.bytesPerSecond))))/秒")
                                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                                }
                                if !job.detail.isEmpty { Text(job.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                            }
                            if !job.state.isTerminal {
                                Button { queue.cancel(job.id) } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).help("取消传输")
                            } else if job.state == .failed || job.state == .cancelled {
                                Button("重试") { queue.retry(job.id) }.controlSize(.small)
                                    .disabled(queue.connectedDeviceID != job.deviceID)
                            }
                        }.padding(.horizontal, 18).padding(.vertical, 9)
                        Divider().padding(.leading, 50)
                    }
                }
            }
        }
    }
    private func bytes(_ count: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(clamping: count), countStyle: .file) }
}
