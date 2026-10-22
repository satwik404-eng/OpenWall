import AppKit

extension Library {
    func installScreenSaver() {
        guard let saver = Bundle.main.url(forResource: "OpenWall", withExtension: "saver") else {
            notice = "This build does not include the OpenWall screen saver. Download the complete app release."
            return
        }
        // The OS installer manages the per-user Screen Savers folder and any
        // confirmation. It never replaces an Apple aerial or lock-screen cache.
        save()
        if !NSWorkspace.shared.open(saver) { notice = "macOS could not open the screen saver installer." }
    }
    func openScreenSaverSettings() {
        let pane = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26
            ? "com.apple.Wallpaper-Settings.extension" : "com.apple.ScreenSaver-Settings.extension"
        if let url = URL(string: "x-apple.systempreferences:\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
