import AppKit
import Observation

@MainActor @Observable final class LockScreenSync {
    var status = "Live lock-screen sync is off"
    var busy = false
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var cache: [String: LockScreenMedia] = [:]
    @ObservationIgnored private var lastApplied: String?

    private var cacheFile: URL { LockScreenRenderer.root.appendingPathComponent("prepared.json") }

    init() {
        let file = LockScreenRenderer.root.appendingPathComponent("prepared.json")
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([String: LockScreenMedia].self, from: data) {
            cache = saved.filter { id, media in
                let currentArtwork = MotionCatalog.byID[id] == nil || media.renderRevision == MotionCatalog.shared.version
                if !currentArtwork, media.movie.deletingLastPathComponent() == LockScreenRenderer.root {
                    try? FileManager.default.removeItem(at: media.movie)
                }
                return currentArtwork && media.movie.deletingLastPathComponent() == LockScreenRenderer.root && FileManager.default.fileExists(atPath: media.movie.path)
            }
        }
    }

    // Reuse expensive transcodes across launches, keeping at most three. These
    // are disposable derived files; imported originals and backups stay intact.
    private func saveCache(keeping id: String) {
        let others = cache.keys.filter { $0 != id }.sorted {
            let left = (try? cache[$0]!.movie.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? cache[$1]!.movie.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left > right
        }
        for key in others.dropFirst(2) {
            if let media = cache.removeValue(forKey: key), media.movie.deletingLastPathComponent() == LockScreenRenderer.root {
                try? FileManager.default.removeItem(at: media.movie)
            }
        }
        if let data = try? JSONEncoder().encode(cache) { try? data.write(to: cacheFile, options: .atomic) }
    }

    func request(_ item: Wallpaper, enabled: Bool, onBattery: Bool, mainScreen: NSScreen?) {
        task?.cancel()
        guard enabled else {
            busy = false
            let ownStill = NSScreen.screens.contains { NSWorkspace.shared.desktopImageURL(for: $0)?.path.hasPrefix(LockScreenRenderer.root.path + "/") == true }
            if NativeLockScreenStore.current.isActive || ownStill { restore() }
            else { status = "Live lock-screen sync is off" }
            return
        }
        busy = true; status = "Preparing matching lock-screen wallpaper…"
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .milliseconds(700))
                try NativeLockScreenStore.current.backupIfNeeded()
                let poster = try await LockScreenRenderer.poster(for: item)
                try Task.checkCancellation()
                if onBattery || ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 26 {
                    try self.applyStill(poster, screen: mainScreen)
                    self.status = onBattery ? "Matching thumbnail on battery" : "Matching thumbnail · live requires macOS 26+"
                } else {
                    // Set the correct still first, so processing failure cannot
                    // leave an unrelated image behind the sign-in prompt.
                    if self.lastApplied == nil { try self.applyStill(poster, screen: mainScreen) }
                    let media: LockScreenMedia
                    if let cached = self.cache[item.id], FileManager.default.fileExists(atPath: cached.movie.path) { media = cached }
                    else { media = try await LockScreenRenderer.prepare(item, poster: poster); self.cache[item.id] = media }
                    try Task.checkCancellation()
                    if self.lastApplied != item.id || !NativeLockScreenStore.current.isActive {
                        try await NativeLockScreenStore.current.install(media, name: item.name)
                    }
                    self.lastApplied = item.id
                    self.saveCache(keeping: item.id)
                    self.status = "Native live lock screen prepared · " + item.name
                }
                self.busy = false
            } catch is CancellationError { }
            catch {
                guard !Task.isCancelled else { return }
                if let poster = try? await LockScreenRenderer.poster(for: item) {
                    try? self.applyStill(poster, screen: mainScreen)
                    self.lastApplied = nil
                    self.status = "Matching thumbnail used. " + error.localizedDescription
                } else { self.status = "Lock-screen update failed: " + error.localizedDescription }
                self.busy = false
            }
        }
    }
    private func applyStill(_ url: URL, screen: NSScreen?) throws {
        for display in NSScreen.screens {
            try NSWorkspace.shared.setDesktopImageURL(url, for: display, options: [.imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue, .allowClipping: true])
        }
    }
    func refreshIfActive() {
        guard NativeLockScreenStore.current.isActive else { return }
        NativeLockScreenStore.refreshAgent()
    }
    func restore() {
        task?.cancel()
        task = Task {
            do { try await NativeLockScreenStore.current.restore(); lastApplied = nil; status = "Previous system wallpaper restored" }
            catch { status = error.localizedDescription }
            busy = false
        }
    }
    func cancel() { task?.cancel(); busy = false }
}
