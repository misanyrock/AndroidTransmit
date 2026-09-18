import SwiftUI

struct DeviceSidebar: View {
    @Bindable var store: BrowserStore
    var body: some View {
        List {
            Section("设备") {
                if store.devices.isEmpty {
                    Label("未连接设备", systemImage: "iphone.slash").foregroundStyle(.secondary)
                }
                ForEach(store.devices) { device in
                    Button { Task { await store.connect(device) } } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(device.name).foregroundStyle(.primary)
                                Text(store.connected?.id == device.id ? "已连接 · USB" : "点击连接").font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "smartphone") }
                    }.buttonStyle(.plain).disabled(store.isLoading || store.transfers.isBusy)
                }
            }
            if !store.storages.isEmpty {
                Section("存储空间") {
                    ForEach(store.storages) { storage in
                        Button { Task { await store.chooseStorage(storage.id) } } label: {
                            HStack {
                                Label(storage.name, systemImage: "internaldrive")
                                Spacer(minLength: 0)
                                if store.storageID == storage.id { Image(systemName: "checkmark").font(.caption).foregroundStyle(Color.accentColor) }
                            }
                            .foregroundStyle(store.storageID == storage.id ? Color.accentColor : Color.primary)
                        }.buttonStyle(.plain).disabled(store.isLoading || store.transfers.isBusy)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 7) {
                Label("USB 文件传输", systemImage: "cable.connector").font(.caption.weight(.medium))
                Text("解锁手机，并将 USB 用途设为“文件传输”。").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
        }
    }
}

struct ConnectionPlaceholder: View {
    let isScanning: Bool
    let retry: () -> Void
    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "cable.connector.horizontal").font(.system(size: 62, weight: .light)).foregroundStyle(Color.accentColor)
            VStack(spacing: 8) {
                Text(isScanning ? "正在连接手机…" : "连接你的 Android 手机").font(.title2.weight(.semibold))
                Text("在 Mac 和 Android 之间，轻松传输文件。").foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 13) {
                step(1, "使用支持数据传输的 USB 线连接手机")
                step(2, "解锁手机，将 USB 用途设为“文件传输”")
                step(3, "如有提示，请在手机上允许访问文件")
            }.padding(.vertical, 8)
            if isScanning { ProgressView().controlSize(.small) }
            else { Button("重新检测", action: retry).buttonStyle(.borderedProminent).controlSize(.large) }
            Text("无需开启 USB 调试").font(.caption).foregroundStyle(.tertiary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(32)
    }
    private func step(_ number: Int, _ title: String) -> some View {
        HStack(spacing: 12) {
            Text("\(number)").font(.caption.weight(.semibold)).frame(width: 23, height: 23).background(.quaternary, in: Circle())
            Text(title).font(.callout).foregroundStyle(.secondary)
        }
    }
}
