import Foundation
import IOKit

struct USBIdentity {
    let registryID: UInt64
    let persistentID: String
    static func find(vendor: UInt16, product: UInt16, address: UInt8) -> USBIdentity? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var matches: [USBIdentity] = []
        while true {
            let object = IOIteratorNext(iterator)
            if object == 0 { break }
            defer { IOObjectRelease(object) }
            func property(_ name: String) -> Any? {
                IORegistryEntryCreateCFProperty(object, name as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            }
            guard (property("idVendor") as? NSNumber)?.uint16Value == vendor,
                  (property("idProduct") as? NSNumber)?.uint16Value == product,
                  (property("USB Address") as? NSNumber)?.uint8Value == address else { continue }
            var id: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(object, &id) == KERN_SUCCESS else { continue }
            let serial = property("USB Serial Number") as? String
            let location = (property("locationID") as? NSNumber)?.stringValue ?? String(id)
            let stable = (serial?.isEmpty == false ? serial! : "port-\(location)")
            matches.append(USBIdentity(registryID: id, persistentID: "\(vendor):\(product):\(stable)"))
        }
        // Ambiguous hardware cannot safely share a persistent transfer identity.
        return matches.count == 1 ? matches[0] : nil
    }
    static func isPresent(registryID: UInt64) -> Bool {
        let object = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(registryID))
        guard object != 0 else { return false }
        IOObjectRelease(object)
        return true
    }
}
