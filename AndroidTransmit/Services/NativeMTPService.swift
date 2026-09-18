import Foundation

/// All libmtp calls and pointer lifetimes belong to this serial queue.
final class NativeMTPService: MTPService, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.androidtransmit.mtp", qos: .userInitiated)
    private var handle: UnsafeMutablePointer<LIBMTP_mtpdevice_t>?
    private var initialized = false

    private func perform<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try body() }) }
        }
    }

    private func device() throws -> UnsafeMutablePointer<LIBMTP_mtpdevice_t> {
        guard let handle else { throw AppFailure("手机已断开，请重新连接。") }
        LIBMTP_Clear_Errorstack(handle)
        return handle
    }

    private func failure(_ operation: String, device: UnsafeMutablePointer<LIBMTP_mtpdevice_t>) -> AppFailure {
        var messages: [String] = []
        var error = LIBMTP_Get_Errorstack(device)
        while let node = error {
            if let text = node.pointee.error_text { messages.append(String(cString: text)) }
            error = node.pointee.next
        }
        LIBMTP_Clear_Errorstack(device)
        return AppFailure("\(operation)失败。请确认手机已解锁、处于文件传输模式且没有被其他传输软件占用。\n" + messages.joined(separator: "\n"))
    }

    func discover() async throws -> [Device] {
        try await perform {
            if !self.initialized { LIBMTP_Init(); self.initialized = true }
            var raw: UnsafeMutablePointer<LIBMTP_raw_device_t>?
            var count: Int32 = 0
            let result = LIBMTP_Detect_Raw_Devices(&raw, &count)
            defer { free(raw) }
            if result == LIBMTP_ERROR_NO_DEVICE_ATTACHED { return [] }
            guard result == LIBMTP_ERROR_NONE else { throw AppFailure("无法扫描 USB 设备。请重新插拔数据线并关闭其他 MTP 软件。") }
            guard let raw else { return [] }
            return (0..<Int(count)).map { index in
                let item = raw[index]
                let name = item.device_entry.product.map { String(cString: $0) } ?? "Android 设备"
                let identity = USBIdentity.find(vendor: item.device_entry.vendor_id, product: item.device_entry.product_id, address: item.devnum)
                return Device(id: identity?.persistentID ?? "session-\(item.bus_location):\(item.devnum)", name: name, bus: item.bus_location, address: item.devnum, registryID: identity?.registryID)
            }
        }
    }

    func connect(_ device: Device) async throws -> [Storage] {
        try await perform {
            if let old = self.handle { LIBMTP_Release_Device(old); self.handle = nil }
            var raw: UnsafeMutablePointer<LIBMTP_raw_device_t>?
            var count: Int32 = 0
            let result = LIBMTP_Detect_Raw_Devices(&raw, &count)
            defer { free(raw) }
            guard result == LIBMTP_ERROR_NONE, let raw else { throw AppFailure("找不到手机，请重新连接并选择文件传输模式。") }
            guard let index = (0..<Int(count)).first(where: { raw[$0].bus_location == device.bus && raw[$0].devnum == device.address }),
                  let opened = LIBMTP_Open_Raw_Device_Uncached(raw.advanced(by: index)) else {
                throw AppFailure("无法打开手机。请解锁屏幕、选择 USB 文件传输，并退出其他传输软件。")
            }
            self.handle = opened
            guard LIBMTP_Get_Storage(opened, 0) == 0 else {
                let error = self.failure("读取存储空间", device: opened)
                LIBMTP_Release_Device(opened); self.handle = nil
                throw error
            }
            var resultStorage: [Storage] = []
            var storage = opened.pointee.storage
            while let node = storage {
                let value = node.pointee
                resultStorage.append(Storage(id: value.id, name: value.StorageDescription.map { String(cString: $0) } ?? "手机存储", capacity: value.MaxCapacity, free: value.FreeSpaceInBytes))
                storage = value.next
            }
            if resultStorage.isEmpty {
                LIBMTP_Release_Device(opened); self.handle = nil
                throw AppFailure("手机没有提供可访问的存储空间。请解锁手机并允许文件访问。")
            }
            return resultStorage
        }
    }

    func disconnect() async {
        _ = try? await perform {
            if let handle = self.handle { LIBMTP_Release_Device(handle); self.handle = nil }
        }
    }

    private func entries(_ device: UnsafeMutablePointer<LIBMTP_mtpdevice_t>, storage: UInt32, parent: UInt32) throws -> [RemoteEntry] {
        var cursor = LIBMTP_Get_Files_And_Folders(device, storage, parent)
        if cursor == nil, LIBMTP_Get_Errorstack(device) != nil { throw failure("读取目录", device: device) }
        var result: [RemoteEntry] = []
        while let node = cursor {
            let file = node.pointee
            result.append(RemoteEntry(id: file.item_id, storageID: file.storage_id, parentID: parent,
                                      name: file.filename.map { String(cString: $0) } ?? "未命名",
                                      size: file.filesize, modified: Date(timeIntervalSince1970: Double(file.modificationdate)),
                                      isFolder: file.filetype == LIBMTP_FILETYPE_FOLDER))
            cursor = file.next
            node.pointee.next = nil
            LIBMTP_destroy_file_t(node)
        }
        return result
    }

    func list(storage: UInt32, parent: UInt32) async throws -> [RemoteEntry] {
        try await perform { try self.entries(self.device(), storage: storage, parent: parent) }
    }

    func createFolder(name: String, storage: UInt32, parent: UInt32) async throws -> UInt32 {
        try await perform {
            try FileRules.validateName(name)
            let d = try self.device()
            guard try !self.entries(d, storage: storage, parent: parent).contains(where: { $0.name == name }) else { throw AppFailure("此目录中已存在“\(name)”。") }
            let text = strdup(name)!; defer { free(text) }
            let id = LIBMTP_Create_Folder(d, text, parent, storage)
            guard id != 0 else { throw self.failure("新建文件夹", device: d) }
            return id
        }
    }

    func rename(_ entry: RemoteEntry, to name: String) async throws {
        try await perform {
            try FileRules.validateName(name)
            let d = try self.device()
            guard try !self.entries(d, storage: entry.storageID, parent: entry.parentID).contains(where: { $0.name == name && $0.id != entry.id }) else { throw AppFailure("此目录中已存在“\(name)”。") }
            guard let file = LIBMTP_Get_Filemetadata(d, entry.id) else { throw self.failure("读取文件属性", device: d) }
            defer { LIBMTP_destroy_file_t(file) }
            guard LIBMTP_Set_File_Name(d, file, name) == 0 else { throw self.failure("重命名", device: d) }
        }
    }

    func delete(_ entry: RemoteEntry) async throws {
        try await perform {
            let d = try self.device()
            func remove(_ item: RemoteEntry) throws {
                if item.isFolder {
                    for child in try self.entries(d, storage: item.storageID, parent: item.id) { try remove(child) }
                }
                guard LIBMTP_Delete_Object(d, item.id) == 0 else { throw self.failure("删除", device: d) }
            }
            try remove(entry)
        }
    }

    func download(_ entry: RemoteEntry, to url: URL, control: TransferControl) async throws {
        try await perform {
            try control.checkCancellation()
            let d = try self.device()
            let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            guard fd >= 0 else { throw AppFailure("无法创建下载临时文件：\(String(cString: strerror(errno)))") }
            defer { close(fd) }
            let result = ATDownload(d, entry.id, fd, control.pointer)
            try control.checkCancellation()
            guard result == 0 else { throw self.failure("下载", device: d) }
            var info = stat()
            guard fstat(fd, &info) == 0, UInt64(info.st_size) == entry.size else { throw AppFailure("下载文件大小不符，未保存为正式文件，请刷新目录后重试。") }
            guard fsync(fd) == 0 else { throw AppFailure("无法写入磁盘，可能空间不足：\(String(cString: strerror(errno)))") }
        }
    }

    func upload(_ url: URL, name: String, storage: UInt32, parent: UInt32, control: TransferControl) async throws {
        try await perform {
            try control.checkCancellation()
            try FileRules.validateName(name)
            let d = try self.device()
            guard try !self.entries(d, storage: storage, parent: parent).contains(where: { $0.name == name }) else { throw AppFailure("目标名称已被占用，请重试：\(name)") }
            let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
            guard fd >= 0 else { throw AppFailure("无法读取本地文件：\(url.lastPathComponent)") }
            defer { close(fd) }
            var info = stat()
            guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { throw AppFailure("仅支持普通文件：\(name)") }
            guard let file = LIBMTP_new_file_t() else { throw AppFailure("无法分配传输缓冲区。") }
            defer { LIBMTP_destroy_file_t(file) }
            file.pointee.filename = strdup(name)
            file.pointee.filesize = UInt64(info.st_size)
            file.pointee.parent_id = parent
            file.pointee.storage_id = storage
            file.pointee.filetype = LIBMTP_FILETYPE_UNKNOWN
            let result = ATUpload(d, fd, file, control.pointer)
            if result != 0 || control.isCancelled {
                let original = self.failure("上传", device: d)
                var cleanupWarning = ""
                if file.pointee.item_id != 0 {
                    if LIBMTP_Delete_Object(d, file.pointee.item_id) != 0 { cleanupWarning = "\n手机中可能残留不完整文件：\(name)，请检查并删除。" }
                } else {
                    cleanupWarning = "\n设备未返回文件编号，请检查手机是否残留不完整文件：\(name)。"
                }
                if control.isCancelled && cleanupWarning.isEmpty { throw CancellationError() }
                throw AppFailure((control.isCancelled ? "传输已取消。" : original.message) + cleanupWarning)
            }
        }
    }
}
