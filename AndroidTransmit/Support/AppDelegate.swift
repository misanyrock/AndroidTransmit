import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: BrowserStore?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store else { return .terminateNow }
        if store.transfers.isBusy {
            let alert = NSAlert()
            alert.messageText = "传输尚未完成"
            alert.informativeText = "退出将取消正在进行和等待中的传输。已完成的文件会保留。"
            alert.addButton(withTitle: "继续传输")
            alert.addButton(withTitle: "取消传输并退出")
            guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        }
        Task {
            await store.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
