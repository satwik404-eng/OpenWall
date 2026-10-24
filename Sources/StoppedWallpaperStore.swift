import AppKit

/// Newer macOS linked aerials can override NSWorkspace's per-Space image API.
/// Split only the desktop choice, retaining the native Idle/screen-saver choice.
struct StoppedWallpaperStore {
    static var index: URL { NativeLockScreenStore.current.index }
    static var ownsDesktop: Bool {
        guard let data = try? Data(contentsOf: index),
              let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let container = root["AllSpacesAndDisplays"] as? [String: Any],
              let desktop = container["Desktop"] as? [String: Any],
              let content = desktop["Content"] as? [String: Any],
              let choice = (content["Choices"] as? [[String: Any]])?.first,
              let config = choice["Configuration"] as? Data,
              let values = try? PropertyListSerialization.propertyList(from: config, format: nil) as? [String: Any],
              let relative = (values["url"] as? [String: String])?["relative"], let url = URL(string: relative) else { return false }
        return url.deletingLastPathComponent() == Storage.root.appendingPathComponent("StoppedFrames")
    }
    static func replacingDesktop(_ data: Data, frames: [String: URL], defaultFrame: URL?) throws -> Data {
        guard var root = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw LockScreenFailure.unavailable("The system wallpaper configuration could not be read.")
        }
        func replace(_ original: [String: Any], with url: URL) throws -> [String: Any] {
            var container = original
            let oldLinked = container.removeValue(forKey: "Linked") as? [String: Any]
            if container["Idle"] == nil, let oldLinked { container["Idle"] = oldLinked }
            let config = try PropertyListSerialization.data(fromPropertyList: ["type": "imageFile", "url": ["relative": url.absoluteString]], format: .binary, options: 0)
            let oldContent = (oldLinked?["Content"] as? [String: Any]) ?? ((container["Desktop"] as? [String: Any])?["Content"] as? [String: Any]) ?? [:]
            container["Desktop"] = ["LastSet": Date(), "LastUse": Date(), "Content": [
                "Choices": [["Provider": "com.apple.wallpaper.choice.image", "Configuration": config, "Files": []]],
                "Shuffle": "$null", "EncodedOptionValues": oldContent["EncodedOptionValues"] ?? "$null"
            ]]
            container["Type"] = container["Idle"] == nil ? "desktop" : "individual"
            return container
        }
        if let url = defaultFrame {
            root["AllSpacesAndDisplays"] = try replace(root["AllSpacesAndDisplays"] as? [String: Any] ?? [:], with: url)
            root["SystemDefault"] = try replace(root["SystemDefault"] as? [String: Any] ?? [:], with: url)
        } else if var global = root["AllSpacesAndDisplays"] as? [String: Any], let linked = global.removeValue(forKey: "Linked") {
            global["Idle"] = linked; global.removeValue(forKey: "Desktop"); global["Type"] = "idle"
            root["AllSpacesAndDisplays"] = global
        }
        var displays = root["Displays"] as? [String: [String: Any]] ?? [:]
        for (uuid, url) in frames { displays[uuid] = try replace(displays[uuid] ?? [:], with: url) }
        root["Displays"] = displays
        if var spaces = root["Spaces"] as? [String: [String: Any]] {
            for key in Array(spaces.keys) {
                if let url = defaultFrame {
                    let oldDefault = spaces[key]?["Default"] as? [String: Any] ?? [:]
                    let replacement = try replace(oldDefault, with: url)
                    spaces[key]?["Default"] = replacement
                }
                var overrides = spaces[key]?["Displays"] as? [String: [String: Any]] ?? [:]
                for (uuid, url) in frames { overrides[uuid] = try replace(overrides[uuid] ?? [:], with: url) }
                spaces[key]?["Displays"] = overrides
            }
            root["Spaces"] = spaces
        }
        return try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
    }
    @MainActor static func install(_ frames: [String: URL], screens: [String: NSScreen]) throws {
        guard !frames.isEmpty else { return }
        var byUUID: [String: URL] = [:]
        for (id, url) in frames {
            if let number = UInt32(id), let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue() {
                byUUID[CFUUIDCreateString(nil, uuid) as String] = url
            }
        }
        let old = try Data(contentsOf: index)
        let backup = Storage.root.appendingPathComponent("StoppedFrames/before-first-quit.plist")
        if !FileManager.default.fileExists(atPath: backup.path) { try old.write(to: backup, options: .atomic) }
        let mainID = NSScreen.main?.wallpaperID ?? screens.keys.sorted().first ?? ""
        let global = frames.count == NSScreen.screens.count ? (frames[mainID] ?? frames.sorted { $0.key < $1.key }.first?.value) : nil
        let updated = try replacingDesktop(old, frames: byUUID, defaultFrame: global)
        try updated.write(to: index, options: .atomic)
        NativeLockScreenStore.refreshAgent()
    }
}
