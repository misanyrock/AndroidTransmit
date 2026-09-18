import SwiftUI

@main
struct AndroidTransmitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = BrowserStore()
    var body: some Scene {
        Window("AndroidTransmit", id: "main") {
            ContentView(store: store)
                .frame(minWidth: 860, minHeight: 540)
                .onAppear { delegate.store = store }
        }
        .defaultSize(width: 1080, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("刷新") { Task { if store.connected == nil { await store.scan() } else { await store.reload() } } }
                    .keyboardShortcut("r").disabled(store.isLoading || store.transfers.isBusy)
            }
        }
    }
}
