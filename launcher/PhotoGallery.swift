import AppKit
import SwiftUI
import ImageIO
import Darwin

private struct PhotoFileIdentity: Equatable {
    let device: Int32, inode: UInt64, changed: Int, nanoseconds: Int
    init(_ info: stat) {
        device = info.st_dev; inode = info.st_ino
        changed = info.st_ctimespec.tv_sec; nanoseconds = info.st_ctimespec.tv_nsec
    }
}

struct PhotoScreenshot: Identifiable {
    let name: String, modified: Date, bytes: Int
    fileprivate let fileIdentity: PhotoFileIdentity
    fileprivate let directoryDevice: Int32, directoryInode: UInt64
    var id: String { name }
}

private struct PhotoGalleryError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct PhotoGalleryStore {
    let folder: URL
    private static let maximumBytes = 64 * 1024 * 1024

    private func directory<T>(_ action: (Int32, stat) throws -> T) throws -> T {
        let url = folder.standardizedFileURL
        guard url.isFileURL, url == url.resolvingSymlinksInPath() else {
            throw PhotoGalleryError(message: "The screenshots folder must not use symbolic links.")
        }
        let fd = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        return try action(fd, info)
    }

    private func screenshot<T>(_ name: String, directory fd: Int32, _ action: (Int32, stat) throws -> T) throws -> T {
        guard !name.contains("/"), name != ".", name != "..", name.lowercased().hasSuffix(".png") else {
            throw PhotoGalleryError(message: "Choose a PNG in the screenshots folder.")
        }
        let file = openat(fd, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard file >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { close(file) }
        var info = stat()
        guard fstat(file, &info) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        guard info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1,
              info.st_size >= 33, info.st_size <= Self.maximumBytes else {
            throw PhotoGalleryError(message: "The screenshot is not a regular PNG smaller than 64 MB.")
        }
        var header = [UInt8](repeating: 0, count: 33)
        guard read(file, &header, header.count) == header.count,
              Array(header[0..<8]) == [137, 80, 78, 71, 13, 10, 26, 10],
              Array(header[8..<16]) == [0, 0, 0, 13, 73, 72, 68, 82] else {
            throw PhotoGalleryError(message: "The screenshot is not a valid PNG.")
        }
        func number(_ offset: Int) -> UInt64 {
            header[offset..<offset + 4].reduce(0) { $0 * 256 + UInt64($1) }
        }
        let width = number(16), height = number(20)
        guard width > 0, height > 0, width <= 16384, height <= 16384, width * height <= 64 * 1024 * 1024 else {
            throw PhotoGalleryError(message: "The screenshot dimensions exceed the gallery limit.")
        }
        guard lseek(file, 0, SEEK_SET) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        return try action(file, info)
    }

    func scan() throws -> (screenshots: [PhotoScreenshot], skipped: Int) {
        do {
            return try directory { fd, parent in
                guard let entries = fdopendir(dup(fd)) else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                defer { closedir(entries) }
                var photos: [PhotoScreenshot] = [], skipped = 0
                while let entry = readdir(entries) {
                    let name = withUnsafePointer(to: &entry.pointee.d_name) {
                        $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
                    }
                    guard name.lowercased().hasSuffix(".png") else { continue }
                    do {
                        let photo = try screenshot(name, directory: fd) { _, info in
                            PhotoScreenshot(name: name, modified: Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec)),
                                            bytes: Int(info.st_size), fileIdentity: PhotoFileIdentity(info),
                                            directoryDevice: parent.st_dev, directoryInode: parent.st_ino)
                        }
                        photos.append(photo)
                    } catch { skipped += 1 }
                }
                photos.sort { $0.modified == $1.modified ? $0.name > $1.name : $0.modified > $1.modified }
                return (photos, skipped)
            }
        } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT) {
            return ([], 0)
        }
    }

    private func selected<T>(_ photo: PhotoScreenshot, _ action: (Int32, Int32, stat) throws -> T) throws -> T {
        try directory { fd, parent in
            guard parent.st_dev == photo.directoryDevice, parent.st_ino == photo.directoryInode else {
                throw PhotoGalleryError(message: "The screenshots folder changed. Refresh the gallery.")
            }
            return try screenshot(photo.name, directory: fd) { file, info in
                guard PhotoFileIdentity(info) == photo.fileIdentity else {
                    throw PhotoGalleryError(message: "The screenshot changed. Refresh the gallery.")
                }
                return try action(fd, file, info)
            }
        }
    }

    private func data(_ photo: PhotoScreenshot) throws -> Data {
        try selected(photo) { _, fd, info in
            var data = Data(count: Int(info.st_size))
            let length = data.count
            try data.withUnsafeMutableBytes { buffer in
                var offset = 0
                while offset < length {
                    let count = read(fd, buffer.baseAddress!.advanced(by: offset), length - offset)
                    if count < 0 && errno == EINTR { continue }
                    guard count > 0 else { throw PhotoGalleryError(message: "The screenshot could not be read. Refresh the gallery.") }
                    offset += count
                }
            }
            return data
        }
    }

    func image(_ photo: PhotoScreenshot, maxPixelSize: Int) throws -> NSImage {
        let bytes = try data(photo)
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: max(1, min(maxPixelSize, 2400)),
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw PhotoGalleryError(message: "The screenshot could not be decoded.") }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    func export(_ photo: PhotoScreenshot, to destination: URL) throws {
        try data(photo).write(to: destination, options: .withoutOverwriting)
    }

    func reveal(_ photo: PhotoScreenshot) throws {
        try selected(photo) { _, _, _ in
            NSWorkspace.shared.activateFileViewerSelecting([folder.appendingPathComponent(photo.name)])
        }
    }

    func delete(_ photo: PhotoScreenshot) throws {
        try selected(photo) { fd, _, info in
            var current = stat()
            guard fstatat(fd, photo.name, &current, AT_SYMLINK_NOFOLLOW) == 0,
                  PhotoFileIdentity(current) == PhotoFileIdentity(info) else {
                throw PhotoGalleryError(message: "The screenshot changed. Refresh the gallery before deleting.")
            }
            guard unlinkat(fd, photo.name, 0) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        }
    }
}

final class PhotoGalleryModel: ObservableObject {
    let store: PhotoGalleryStore
    @Published var photos: [PhotoScreenshot] = []
    @Published var selection: String?
    @Published var preview: NSImage?
    @Published var status = ""
    private var thumbnails: [String: NSImage] = [:]
    var selected: PhotoScreenshot? { photos.first { $0.id == selection } }
    init(folder: URL) { store = PhotoGalleryStore(folder: folder); refresh() }
    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { status = error.localizedDescription }
    }
    func refresh() {
        perform {
            let result = try store.scan()
            photos = result.screenshots; thumbnails.removeAll()
            if !photos.contains(where: { $0.id == selection }) { selection = photos.first?.id }
            status = result.skipped == 0 ? "\(photos.count) screenshots" : "\(photos.count) screenshots. Skipped \(result.skipped) unsafe or damaged PNG files."
            updatePreview()
        }
    }
    func thumbnail(_ photo: PhotoScreenshot) -> NSImage? {
        if let image = thumbnails[photo.id] { return image }
        guard let image = try? store.image(photo, maxPixelSize: 160) else { return nil }
        // shortcut: keep at most 100 thumbnails, revisit if large galleries need a disk cache.
        if thumbnails.count >= 100 { thumbnails.removeAll() }
        thumbnails[photo.id] = image; return image
    }
    func updatePreview() {
        preview = nil
        guard let photo = selected else { return }
        perform { preview = try store.image(photo, maxPixelSize: 1600) }
    }
    func reveal() { guard let photo = selected else { return }; perform { try store.reveal(photo) } }
    func export() {
        guard let photo = selected else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = photo.name; panel.allowedFileTypes = ["png"]
        panel.message = "Choose a new filename to export this screenshot."
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        perform { try store.export(photo, to: destination); status = "Screenshot exported." }
    }
    func delete() {
        guard let photo = selected else { return }
        let alert = NSAlert(); alert.alertStyle = .warning; alert.messageText = "Delete this screenshot?"
        alert.informativeText = "\(photo.name) will be permanently deleted from the screenshots folder."
        alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Delete")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        perform { try store.delete(photo); refresh() }
    }
}

struct PhotoGalleryView: View {
    @ObservedObject var model: PhotoGalleryModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Screenshots").font(.title2)
                Spacer()
                Button("Refresh", action: model.refresh)
            }
            HSplitView {
                List(selection: $model.selection) {
                    ForEach(model.photos) { photo in
                        HStack(spacing: 10) {
                            Group {
                                if let image = model.thumbnail(photo) { Image(nsImage: image).resizable().scaledToFit() }
                                else { Image(systemName: "photo").foregroundColor(.secondary) }
                            }.frame(width: 100, height: 64)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(photo.name).lineLimit(1)
                                Text(photo.modified, style: .date).font(.caption).foregroundColor(.secondary)
                            }
                        }.padding(.vertical, 3).tag(photo.id)
                    }
                }.frame(minWidth: 260, idealWidth: 300, maxWidth: 380)
                ZStack {
                    Color.black.opacity(0.25)
                    if let image = model.preview { Image(nsImage: image).resizable().scaledToFit().padding(12) }
                    else { Text(model.photos.isEmpty ? "No screenshots yet. Capture one in photo mode." : "Select a screenshot to preview.").foregroundColor(.secondary).padding() }
                }.frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
            }.frame(minHeight: 320)
            HStack {
                Button("Reveal in Finder", action: model.reveal).disabled(model.selected == nil)
                Button("Export PNG...", action: model.export).disabled(model.selected == nil)
                Spacer()
                Button("Delete...", action: model.delete).disabled(model.selected == nil)
            }
            Text(model.status).font(.callout).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(18).frame(minWidth: 700, minHeight: 460)
            .onChange(of: model.selection) { _ in model.updatePreview() }
    }
}

enum PhotoGalleryWindow {
    private static var window: NSWindow?
    private static var model: PhotoGalleryModel?
    static func show(folder: URL) {
        if let existing = window, existing.isVisible, model?.store.folder == folder {
            model?.refresh(); existing.makeKeyAndOrderFront(nil); return
        }
        let model = PhotoGalleryModel(folder: folder)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 600), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "NFSU2 Screenshots"; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: PhotoGalleryView(model: model))
        window.center(); window.makeKeyAndOrderFront(nil)
        self.window = window; self.model = model
    }
}
