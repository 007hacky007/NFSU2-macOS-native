import AppKit
import Foundation

@main struct PhotoGalleryTests {
    static func check(_ condition: Bool, _ message: String) {
        if !condition { fatalError(message) }
    }
    static func rejects(_ message: String, _ operation: () throws -> Void) {
        do { try operation(); fatalError(message) } catch { }
    }
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("nfsu2-gallery-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let folder = root.appendingPathComponent("Screenshots")
        let store = PhotoGalleryStore(folder: folder)
        check(try store.scan().screenshots.isEmpty, "Missing capture folder should be empty")
        check(!fm.fileExists(atPath: folder.path), "Browsing must not create a screenshot folder")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 3, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let png = bitmap.representation(using: .png, properties: [:])!
        let older = folder.appendingPathComponent("old.png"), newest = folder.appendingPathComponent("new.png")
        try png.write(to: older); try png.write(to: newest)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: older.path)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 200)], ofItemAtPath: newest.path)
        let outside = root.appendingPathComponent("outside.png"); try png.write(to: outside)
        try fm.createSymbolicLink(at: folder.appendingPathComponent("linked.png"), withDestinationURL: outside)
        try fm.linkItem(at: outside, to: folder.appendingPathComponent("hardlink.png"))
        try Data("not a png".utf8).write(to: folder.appendingPathComponent("broken.png"))
        try png.write(to: folder.appendingPathComponent("ignored.jpg"))
        let scan = try store.scan()
        check(scan.screenshots.map { $0.name } == ["new.png", "old.png"], "Only valid direct PNGs should list, newest first")
        check(scan.skipped == 3, "Unsafe or damaged PNGs should be reported")
        let selected = scan.screenshots[0]
        check(try store.image(selected, maxPixelSize: 2).size.width <= 2, "Thumbnail decoding should downsample")
        let exported = root.appendingPathComponent("export.png")
        try store.export(selected, to: exported)
        check(try Data(contentsOf: exported) == png, "Export should preserve PNG bytes")
        rejects("Export must not replace an existing user file") { try store.export(selected, to: exported) }
        check(try Data(contentsOf: exported) == png, "Failed export should preserve the existing file")
        try fm.removeItem(at: newest)
        try fm.createSymbolicLink(at: newest, withDestinationURL: outside)
        rejects("Replaced screenshot symlink must not be read") { _ = try store.image(selected, maxPixelSize: 32) }
        rejects("Replaced screenshot symlink must not be deleted") { try store.delete(selected) }
        check(fm.fileExists(atPath: outside.path), "Outside file must survive rejected deletion")
        try fm.removeItem(at: newest); try png.write(to: newest)
        rejects("A stale selection must not delete a replacement file") { try store.delete(selected) }
        let current = try store.scan().screenshots.first { $0.name == "new.png" }!
        try store.delete(current)
        check(!fm.fileExists(atPath: newest.path), "Delete should remove only the selected screenshot")
        check(fm.fileExists(atPath: older.path) && fm.fileExists(atPath: outside.path), "Delete must preserve other files")
        let alias = root.appendingPathComponent("alias")
        try fm.createSymbolicLink(at: alias, withDestinationURL: folder)
        rejects("Gallery folder symlinks must be rejected") { _ = try PhotoGalleryStore(folder: alias).scan() }
        var oversized = png
        oversized.replaceSubrange(16..<20, with: [0, 1, 0, 0])
        try oversized.write(to: folder.appendingPathComponent("huge.png"))
        check(!(try store.scan()).screenshots.contains { $0.name == "huge.png" }, "Oversized dimensions must be rejected before decoding")
        let large = folder.appendingPathComponent("large.png")
        try png.write(to: large)
        let largeFile = try FileHandle(forWritingTo: large)
        try largeFile.truncate(atOffset: 64 * 1024 * 1024 + 1); try largeFile.close()
        check(!(try store.scan()).screenshots.contains { $0.name == "large.png" }, "Oversized files must be rejected before reading")
        let renamed = root.appendingPathComponent("old-folder")
        let previous = try store.scan().screenshots.first { $0.name == "old.png" }!
        try fm.moveItem(at: folder, to: renamed)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try png.write(to: folder.appendingPathComponent("old.png"))
        rejects("A replaced screenshot directory must not be deleted from") { try store.delete(previous) }
        check(fm.fileExists(atPath: folder.appendingPathComponent("old.png").path), "Replacement folder file must survive")
        print("photo_gallery: listing, bounded decoding, safe export and selected deletion passed")
    }
}
