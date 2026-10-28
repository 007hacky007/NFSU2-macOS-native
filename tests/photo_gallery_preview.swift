import AppKit

@main struct PhotoGalleryPreview {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1]).resolvingSymlinksInPath()
        let folder = root.appendingPathComponent("Screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        for (index, title) in ["Bayview at dusk", "Harbor lights", "Coastal sprint"].enumerated() {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 960, pixelsHigh: 540, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            NSGradient(starting: NSColor(calibratedHue: CGFloat(index) * 0.16 + 0.5, saturation: 0.8, brightness: 0.5, alpha: 1), ending: .black)!.draw(in: NSRect(x: 0, y: 0, width: 960, height: 540), angle: -90)
            NSColor(white: 0.15, alpha: 1).setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: 960, height: 160)).fill()
            NSColor.systemOrange.setFill()
            NSBezierPath(roundedRect: NSRect(x: 280, y: 120, width: 400, height: 110), xRadius: 35, yRadius: 35).fill()
            (title as NSString).draw(at: NSPoint(x: 40, y: 440), withAttributes: [.font: NSFont.systemFont(ofSize: 38, weight: .bold), .foregroundColor: NSColor.white])
            NSGraphicsContext.restoreGraphicsState()
            try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("NFSU2-20261028-12000\(index).png"))
        }
        PhotoGalleryWindow.show(folder: folder)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            guard let window = app.windows.first, let capture = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), .boundsIgnoreFraming) else { fatalError("No gallery window") }
            let rep = NSBitmapImageRep(cgImage: capture)
            try! rep.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("photo-gallery.png"))
            app.stop(nil)
            app.postEvent(NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!, atStart: false)
        }
        app.run()
        print("photo_gallery_preview: synthetic screenshots captured")
    }
}
