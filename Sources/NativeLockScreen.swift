import AppKit

/// Experimental per-user Aerial integration on macOS 26+. The native manifest
/// and linked-wallpaper schema were informed by CaveWall (MIT); see notices.
/// Apple originals are never replaced. Backups belong to OpenWall's own library.
struct NativeLockScreenStore {
    static let category = "0A110A11-0000-4000-8000-000000000001"
    static let subcategory = "0A110A11-0000-4000-8000-000000000002"
    let wallpaperRoot: URL
    let backupRoot: URL
    var manifest: URL { wallpaperRoot.appendingPathComponent("aerials/manifest/entries.json") }
    var index: URL { wallpaperRoot.appendingPathComponent("Store/Index.plist") }
    var videos: URL { wallpaperRoot.appendingPathComponent("aerials/videos") }
    var thumbnails: URL { wallpaperRoot.appendingPathComponent("aerials/thumbnails") }
    var record: URL { backupRoot.appendingPathComponent("active-native-asset.txt") }

    static var current: Self {
        Self(wallpaperRoot: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("com.apple.wallpaper"),
             backupRoot: Storage.root.appendingPathComponent("LockScreen/Backups"))
    }

    func backupIfNeeded() throws {
        guard FileManager.default.fileExists(atPath: index.path), FileManager.default.fileExists(atPath: manifest.path) else {
            throw LockScreenFailure.unavailable("This macOS version does not expose the native aerial cache. A matching still thumbnail will be used.")
        }
        try FileManager.default.createDirectory(at: backupRoot, withIntermediateDirectories: true)
        for (source, name) in [(index, "original-index.plist"), (manifest, "original-entries.json")] {
            let destination = backupRoot.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: destination.path) { try Data(contentsOf: source).write(to: destination, options: .atomic) }
        }
    }

    static func manifestByAdding(_ data: Data, id: String, name: String, movie: URL, poster: URL) throws -> Data {
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw LockScreenFailure.unavailable("The macOS aerial manifest could not be read.") }
        var categories = json["categories"] as? [[String: Any]] ?? []
        var assets = json["assets"] as? [[String: Any]] ?? []
        categories.removeAll { $0["id"] as? String == category }
        assets.removeAll { ($0["subcategories"] as? [String])?.contains(subcategory) == true }
        categories.append([
            "id": category, "localizedNameKey": "OpenWall", "localizedDescriptionKey": "Your local OpenWall wallpapers",
            "previewImage": poster.absoluteString, "representativeAssetID": id, "preferredOrder": 99,
            "subcategories": [["id": subcategory, "localizedNameKey": "OpenWall", "localizedDescriptionKey": "Your local OpenWall wallpapers", "previewImage": poster.absoluteString, "representativeAssetID": id, "preferredOrder": 0]]
        ])
        assets.append([
            "id": id, "shotID": "OPENWALL_LOCAL", "localizedNameKey": name, "accessibilityLabel": name,
            "previewImage": poster.absoluteString, "url-4K-SDR-240FPS": movie.absoluteString,
            "categories": [category], "subcategories": [subcategory], "includeInShuffle": false,
            "showInTopLevel": true, "preferredOrder": 0, "pointsOfInterest": ["0": "OPENWALL_LOCAL_0"]
        ])
        json["categories"] = categories; json["assets"] = assets
        return try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
    }

    static func linkedIndex(_ data: Data, id: String) throws -> Data {
        guard var plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw LockScreenFailure.unavailable("The macOS wallpaper store could not be read.")
        }
        let config = try PropertyListSerialization.data(fromPropertyList: ["assetID": id], format: .binary, options: 0)
        let options = try firstOptions(plist) ?? PropertyListSerialization.data(fromPropertyList: ["values": ["placement": ["picker": ["_0": ["id": "FillScreen"]]]]], format: .binary, options: 0)
        let linked: [String: Any] = ["LastSet": Date(), "LastUse": Date(), "Content": [
            "Choices": [["Provider": "com.apple.wallpaper.choice.aerials", "Files": [], "Configuration": config]], "Shuffle": "$null", "EncodedOptionValues": options
        ]]
        func replace(_ original: [String: Any]) -> [String: Any] {
            var result = original
            result.removeValue(forKey: "Desktop"); result.removeValue(forKey: "Idle")
            result["Type"] = "linked"; result["Linked"] = linked
            return result
        }
        plist["AllSpacesAndDisplays"] = replace(plist["AllSpacesAndDisplays"] as? [String: Any] ?? [:])
        plist["SystemDefault"] = replace(plist["SystemDefault"] as? [String: Any] ?? [:])
        // Preserve Space/display identities and unknown metadata; replace only
        // their wallpaper content. Native lock-screen sync follows the main
        // display's current OpenWall wallpaper on every screen.
        if let displays = plist["Displays"] as? [String: [String: Any]] { plist["Displays"] = displays.mapValues(replace) }
        if var spaces = plist["Spaces"] as? [String: [String: Any]] {
            for key in Array(spaces.keys) {
                if let value = spaces[key]?["Default"] as? [String: Any] { spaces[key]?["Default"] = replace(value) }
                if let displays = spaces[key]?["Displays"] as? [String: [String: Any]] { spaces[key]?["Displays"] = displays.mapValues(replace) }
            }
            plist["Spaces"] = spaces
        }
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
    }

    private static func firstOptions(_ object: Any) -> Data? {
        if let dict = object as? [String: Any] {
            if let data = dict["EncodedOptionValues"] as? Data { return data }
            for value in dict.values { if let found = firstOptions(value) { return found } }
        }
        if let array = object as? [Any] { for value in array { if let found = firstOptions(value) { return found } } }
        return nil
    }

    static func keepingScreenSaver(_ data: Data, module: URL) throws -> Data {
        guard var root = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw LockScreenFailure.unavailable("The screen-saver configuration could not be read.")
        }
        let configuration = try PropertyListSerialization.data(fromPropertyList: ["module": ["relative": module.absoluteString]], format: .binary, options: 0)
        let idle: [String: Any] = ["LastSet": Date(), "LastUse": Date(), "Content": [
            "Choices": [["Provider": "com.apple.wallpaper.choice.screen-saver", "Files": [], "Configuration": configuration]],
            "Shuffle": "$null", "EncodedOptionValues": "$null"
        ]]
        func replace(_ original: [String: Any]) -> [String: Any] {
            var container = original
            if let linked = container.removeValue(forKey: "Linked") { container["Desktop"] = linked }
            container["Idle"] = idle
            container["Type"] = container["Desktop"] == nil ? "idle" : "individual"
            return container
        }
        for key in ["AllSpacesAndDisplays", "SystemDefault"] { root[key] = replace(root[key] as? [String: Any] ?? [:]) }
        if let displays = root["Displays"] as? [String: [String: Any]] { root["Displays"] = displays.mapValues(replace) }
        if var spaces = root["Spaces"] as? [String: [String: Any]] {
            for key in Array(spaces.keys) {
                let oldDefault = spaces[key]?["Default"] as? [String: Any] ?? [:]
                spaces[key]?["Default"] = replace(oldDefault)
                if let displays = spaces[key]?["Displays"] as? [String: [String: Any]] { spaces[key]?["Displays"] = displays.mapValues(replace) }
            }
            root["Spaces"] = spaces
        }
        return try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
    }

    var isActive: Bool {
        guard let id = try? String(contentsOf: record, encoding: .utf8),
              let data = try? Data(contentsOf: index),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let container = plist["AllSpacesAndDisplays"] as? [String: Any],
              let linked = (container["Linked"] ?? container["Desktop"]) as? [String: Any], let content = linked["Content"] as? [String: Any],
              let choice = (content["Choices"] as? [[String: Any]])?.first,
              choice["Provider"] as? String == "com.apple.wallpaper.choice.aerials",
              let config = choice["Configuration"] as? Data,
              let values = try? PropertyListSerialization.propertyList(from: config, format: nil) as? [String: Any] else { return false }
        return values["assetID"] as? String == id
    }

    @MainActor func install(_ media: LockScreenMedia, name: String) async throws {
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 else { throw LockScreenFailure.unavailable("Live lock-screen integration requires macOS 26 or later.") }
        try backupIfNeeded()
        let fm = FileManager.default
        try fm.createDirectory(at: videos, withIntermediateDirectories: true)
        try fm.createDirectory(at: thumbnails, withIntermediateDirectories: true)
        let movie = videos.appendingPathComponent(media.id + ".mov"), poster = thumbnails.appendingPathComponent(media.id + ".jpg")
        if !fm.fileExists(atPath: movie.path) { try fm.copyItem(at: media.movie, to: movie) }
        try Data(contentsOf: media.poster).write(to: poster, options: .atomic)
        let oldManifest = try Data(contentsOf: manifest)
        let oldJSON = try JSONSerialization.jsonObject(with: oldManifest) as? [String: Any]
        let oldIDs = (oldJSON?["assets"] as? [[String: Any]] ?? []).filter { ($0["subcategories"] as? [String])?.contains(Self.subcategory) == true }.compactMap { $0["id"] as? String }.filter { UUID(uuidString: $0) != nil }
        let manifestData = try Self.manifestByAdding(oldManifest, id: media.id, name: name, movie: movie, poster: poster)
        try Task.checkCancellation()
        Self.refreshAgent()
        try await Task.sleep(for: .milliseconds(300))
        let linked = try Self.linkedIndex(Data(contentsOf: index), id: media.id)
        let saver = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Screen Savers/OpenWall.saver")
        let newIndex = try fm.fileExists(atPath: saver.path) ? Self.keepingScreenSaver(linked, module: saver) : linked
        // After this point finish the small commit even if a later selection
        // cancels preparation. A cancelled operation must not leave half a store.
        try manifestData.write(to: manifest, options: .atomic)
        do { try newIndex.write(to: index, options: .atomic) }
        catch { try? oldManifest.write(to: manifest, options: .atomic); Self.refreshAgent(); throw error }
        try media.id.write(to: record, atomically: true, encoding: .utf8)
        Self.refreshAgent()
        // Only remove IDs identified as OpenWall-owned in the old manifest.
        // Apple downloads and third-party cache files are never enumerated.
        for id in oldIDs where id != media.id {
            try? fm.removeItem(at: videos.appendingPathComponent(id + ".mov"))
            try? fm.removeItem(at: thumbnails.appendingPathComponent(id + ".jpg"))
        }
    }

    @MainActor func restore() async throws {
        let ownStill = NSScreen.screens.contains { screen in
            NSWorkspace.shared.desktopImageURL(for: screen)?.path.hasPrefix(backupRoot.deletingLastPathComponent().path + "/") == true
        }
        guard isActive || ownStill || StoppedWallpaperStore.ownsDesktop else { throw LockScreenFailure.unavailable("The system wallpaper changed outside OpenWall. It was left untouched; your original backup remains in the local library.") }
        Self.refreshAgent(); try await Task.sleep(for: .milliseconds(300))
        try Data(contentsOf: backupRoot.appendingPathComponent("original-index.plist")).write(to: index, options: .atomic)
        // Remove only OpenWall metadata, preserving Apple and other app entries.
        if var json = try JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any] {
            json["categories"] = (json["categories"] as? [[String: Any]] ?? []).filter { $0["id"] as? String != Self.category }
            json["assets"] = (json["assets"] as? [[String: Any]] ?? []).filter { ($0["subcategories"] as? [String])?.contains(Self.subcategory) != true }
            try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]).write(to: manifest, options: .atomic)
        }
        Self.refreshAgent()
    }

    static func refreshAgent() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["-u", NSUserName(), "WallpaperAgent", "WallpaperAerialsExtension"]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try? process.run(); process.waitUntilExit()
    }
}
