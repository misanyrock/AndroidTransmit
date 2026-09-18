import Foundation
import IOKit
import IOKit.usb

/// Callbacks are installed on the main run loop. Drain iterators to re-arm notifications.
final class USBWatcher {
    private var port: IONotificationPortRef?
    private var added: io_iterator_t = 0
    private var removed: io_iterator_t = 0
    private let changed: () -> Void
    init(changed: @escaping () -> Void) {
        self.changed = changed
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        self.port = port
        let source = IONotificationPortGetRunLoopSource(port).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, IOServiceMatching("IOUSBHostDevice"), { context, iterator in
            USBWatcher.drain(iterator)
            if let context { Unmanaged<USBWatcher>.fromOpaque(context).takeUnretainedValue().changed() }
        }, context, &added)
        Self.drain(added)
        IOServiceAddMatchingNotification(port, kIOTerminatedNotification, IOServiceMatching("IOUSBHostDevice"), { context, iterator in
            USBWatcher.drain(iterator)
            if let context { Unmanaged<USBWatcher>.fromOpaque(context).takeUnretainedValue().changed() }
        }, context, &removed)
        Self.drain(removed)
    }
    private static func drain(_ iterator: io_iterator_t) {
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            IOObjectRelease(service)
        }
    }
    deinit {
        if added != 0 { IOObjectRelease(added) }
        if removed != 0 { IOObjectRelease(removed) }
        if let port { IONotificationPortDestroy(port) }
    }
}
