import AppKit

@main struct SaveManagerPreview {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let saves = root.appendingPathComponent("saves"), registry = root.appendingPathComponent("registry")
        var profile = Data(repeating:0,count:54966)
        profile.replaceSubrange(0..<4,with:Data("20CM".utf8))
        for (at,value) in [(4,54966),(8,8),(12,54930),(28,0x10d),(32,54930)] { profile.put32(at,UInt32(value)) }
        profile.replaceSubrange(53797..<53801,with:Data("TEST".utf8))
        for i in 0..<48 { profile.put32(36 + i * 24 + 20,UInt32.max) }
        profile.put32(16,SaveProfile.checksum(Data(profile[28..<36])))
        profile.put32(20,SaveProfile.checksum(Data(profile[36...])))
        profile.put32(24,SaveProfile.checksum(Data(profile[..<24])))
        let target = saves.appendingPathComponent("NFS Underground 2/TEST/TEST")
        try FileManager.default.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
        try profile.write(to:target)
        let app = NSApplication.shared; app.setActivationPolicy(.accessory)
        SaveManagerWindow.show(saves:saves,registry:registry,serverURL:"ws://localhost:28766/lan",gameRunning:{ false })
        DispatchQueue.main.asyncAfter(deadline:.now() + 1) {
            guard let window = app.windows.first, let capture = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), .boundsIgnoreFraming) else { fatalError("No preview window image") }
            let image = NSBitmapImageRep(cgImage:capture)
            try! image.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent("save-manager.png"))
            app.stop(nil)
            app.postEvent(NSEvent.otherEvent(with:.applicationDefined,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,subtype:0,data1:0,data2:0)!,atStart:false)
        }
        app.run()
        print("save_manager_preview: synthetic local saves and cloud opt-in UI captured")
    }
}
