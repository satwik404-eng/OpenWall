import AppKit
import AVFoundation
import Observation
import ServiceManagement
import UniformTypeIdentifiers

struct Wallpaper: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let filename: String?
    var isVideo: Bool { filename != nil }
    static let presets = [
        Wallpaper(id: "aurora", name: "Northern lights", filename: nil),
        Wallpaper(id: "dusk", name: "Afterglow", filename: nil),
        Wallpaper(id: "ocean", name: "Deep current", filename: nil),
        Wallpaper(id: "ember", name: "Ember glow", filename: nil),
        Wallpaper(id: "amethyst", name: "Amethyst drift", filename: nil),
        Wallpaper(id: "glacier", name: "Glacier light", filename: nil),
        Wallpaper(id: "solar", name: "Solar tide", filename: nil),
        Wallpaper(id: "midnight", name: "Midnight silk", filename: nil),
        Wallpaper(id: "rose", name: "Rosewater", filename: nil)
    ]
}

struct LibraryState: Codable {
    var videos: [Wallpaper] = []
    var assignments: [String: String] = [:]
    var manualPause = false
    var pauseOnBattery = true
    var pauseInFullScreen = true
    var liveLockScreen = false
    var playlist: [PlaylistEntry] = []
    var playlistPlayback: [String: PlaylistPlayback] = [:]
    var speed = 1.0

    init() {}

    private enum CodingKeys: String, CodingKey {
        case videos, assignments, manualPause, pauseOnBattery, pauseInFullScreen, liveLockScreen, playlist, playlistPlayback, speed
    }
    private enum LegacyKeys: String, CodingKey { case shuffleMinutes }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        videos = try values.decodeIfPresent([Wallpaper].self, forKey: .videos) ?? []
        assignments = try values.decodeIfPresent([String: String].self, forKey: .assignments) ?? [:]
        manualPause = try values.decodeIfPresent(Bool.self, forKey: .manualPause) ?? false
        pauseOnBattery = try values.decodeIfPresent(Bool.self, forKey: .pauseOnBattery) ?? true
        pauseInFullScreen = try values.decodeIfPresent(Bool.self, forKey: .pauseInFullScreen) ?? true
        liveLockScreen = try values.decodeIfPresent(Bool.self, forKey: .liveLockScreen) ?? false
        playlist = try values.decodeIfPresent([PlaylistEntry].self, forKey: .playlist) ?? []
        playlistPlayback = try values.decodeIfPresent([String: PlaylistPlayback].self, forKey: .playlistPlayback) ?? [:]
        speed = try values.decodeIfPresent(Double.self, forKey: .speed) ?? 1
        if !values.contains(.playlist) {
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            let minutes = try legacy.decodeIfPresent(Int.self, forKey: .shuffleMinutes) ?? 0
            if minutes > 0 {
                let duration = WallpaperDuration.allCases.filter { $0 != .forever && $0.rawValue >= minutes * 60 }.min { $0.rawValue < $1.rawValue } ?? .oneDay
                playlist = (Wallpaper.presets + videos).map { PlaylistEntry(wallpaperID: $0.id, duration: duration) }
                for (screenID, wallpaperID) in assignments {
                    if let entry = playlist.first(where: { $0.wallpaperID == wallpaperID }) {
                        playlistPlayback[screenID] = PlaylistPlayback(entryID: entry.id, remainingSeconds: duration.seconds)
                    }
                }
            }
        }
    }
}

struct Display: Identifiable, Equatable {
    let id: String
    let name: String
}

enum Storage {
    static var root: URL {
        if let override = ProcessInfo.processInfo.environment["OPENWALL_DATA_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("org.openwall.desktop", isDirectory: true)
    }
    static var media: URL { root.appendingPathComponent("Media", isDirectory: true) }
    static var thumbnails: URL { root.appendingPathComponent("Thumbnails", isDirectory: true) }
    static var stateFile: URL { root.appendingPathComponent("library.json") }
    static func prepare() throws {
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: thumbnails, withIntermediateDirectories: true)
    }
    static func save(_ state: LibraryState) throws {
        try prepare()
        try JSONEncoder().encode(state).write(to: stateFile, options: .atomic)
    }
    static func load() throws -> LibraryState {
        guard FileManager.default.fileExists(atPath: stateFile.path) else { return LibraryState() }
        return try JSONDecoder().decode(LibraryState.self, from: Data(contentsOf: stateFile))
    }
}

struct ImportedVideo: Sendable {
    let id: String
    let name: String
    let filename: String
}

enum VideoImporter {
    static func importFile(_ url: URL) async throws -> ImportedVideo {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let asset = AVURLAsset(url: url)
        let playable = try await asset.load(.isPlayable)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let duration = try await asset.load(.duration)
        guard playable, !tracks.isEmpty, duration.seconds.isFinite, duration.seconds > 0 else {
            throw NSError(domain: "OpenWall", code: 1, userInfo: [NSLocalizedDescriptionKey: "This file does not contain a playable video."])
        }
        let id = UUID().uuidString
        let filename = id + "." + url.pathExtension.lowercased()
        try Storage.prepare()
        let destination = Storage.media.appendingPathComponent(filename)
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.copyItem(at: url, to: destination)
        }.value
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 450)
        if let frame = try? await generator.image(at: .zero) {
            let bitmap = NSBitmapImageRep(cgImage: frame.image)
            if let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
                try? data.write(to: Storage.thumbnails.appendingPathComponent(id + ".jpg"), options: .atomic)
            }
        }
        return ImportedVideo(id: id, name: url.deletingPathExtension().lastPathComponent, filename: filename)
    }
}

@MainActor @Observable
final class Library {
    static let shared = Library()
    var state = LibraryState()
    var displays: [Display] = []
    var target = "all"
    var selection = "aurora"
    var section = "All wallpapers"
    var search = ""
    var notice: String?
    var importing = false
    var battery = false
    var sleeping = false
    var sessionLocked = false
    let lockScreen = LockScreenSync()
    private(set) var fullScreenActive = false
    var loginEnabled = false
    @ObservationIgnored var engine: WallpaperEngine?
    @ObservationIgnored private var batteryTimer: Timer?
    @ObservationIgnored var playlistTimer: Timer?
    @ObservationIgnored var playlistAnchors: [String: TimeInterval] = [:]
    @ObservationIgnored let clock: @MainActor () -> TimeInterval
    @ObservationIgnored private var fullScreenTimer: Timer?
    @ObservationIgnored private let fullScreenProbe: @MainActor () -> Bool
    @ObservationIgnored private var tokens: [NSObjectProtocol] = []
    @ObservationIgnored private var started = false

    var wallpapers: [Wallpaper] { Wallpaper.presets + state.videos }
    var selected: Wallpaper { wallpapers.first { $0.id == selection } ?? Wallpaper.presets[0] }
    var filtered: [Wallpaper] {
        wallpapers.filter { item in
            (section != "My videos" || item.isVideo) && (section != "Motion collection" || !item.isVideo)
            && (search.isEmpty || item.name.localizedCaseInsensitiveContains(search))
        }
    }
    var paused: Bool { state.manualPause || sleeping || sessionLocked || (state.pauseOnBattery && battery) || (state.pauseInFullScreen && fullScreenActive) }
    var status: String {
        if state.assignments.isEmpty { return "Ready when you are" }
        if state.manualPause { return "Paused by you" }
        if sessionLocked { return "Session locked · desktop paused" }
        if sleeping { return "Display asleep" }
        if state.pauseInFullScreen && fullScreenActive { return "Paused in full screen" }
        if state.pauseOnBattery && battery { return "Paused on battery" }
        return "Wallpaper is live"
    }

    init(fullScreenProbe: @escaping @MainActor () -> Bool = { FullScreenDetector.isActive },
         clock: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.fullScreenProbe = fullScreenProbe
        self.clock = clock
        do { state = try Storage.load() }
        catch { notice = "Your saved library could not be read. The original file is untouched. \(error.localizedDescription)" }
    }

    func start() {
        guard !started else { return }
        started = true
        engine = WallpaperEngine()
        refreshDisplays()
        battery = Power.isOnBattery
        loginEnabled = SMAppService.mainApp.status == .enabled
        engine?.onError = { [weak self] message in self?.notice = message }
        restore()
        syncLockScreen()
        let center = NSWorkspace.shared.notificationCenter
        for (name, locked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            tokens.append(DistributedNotificationCenter.default().addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.sessionLocked = locked
                    self.updatePlayback()
                    if locked && self.state.liveLockScreen && !(self.state.pauseOnBattery && self.battery) { self.lockScreen.refreshIfActive() }
                }
            })
        }
        for (name, sleep) in [(NSWorkspace.willSleepNotification, true), (NSWorkspace.screensDidSleepNotification, true), (NSWorkspace.didWakeNotification, false), (NSWorkspace.screensDidWakeNotification, false)] {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.sleeping = sleep; self?.updatePlayback() }
            })
        }
        tokens.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.updatePlayback(); self?.engine?.reorder() }
        })
        tokens.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.updatePlayback() }
        })
        tokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshDisplays(); self?.restore() }
        })
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let currentBattery = Power.isOnBattery
                guard self.battery != currentBattery else { return }
                self.battery = currentBattery
                self.updatePlayback()
                self.syncLockScreen()
            }
        }
    }

    func refreshDisplays() {
        checkpointPlaylistClocks()
        displays = NSScreen.screens.map { Display(id: $0.wallpaperID, name: $0.localizedName) }
        if target != "all", !displays.contains(where: { $0.id == target }) { target = "all" }
    }

    func save() {
        do { try Storage.save(state) }
        catch { notice = "Could not save settings: \(error.localizedDescription)" }
    }

    func stopMonitoring() {
        batteryTimer?.invalidate()
        fullScreenTimer?.invalidate()
        batteryTimer = nil
        fullScreenTimer = nil
        for token in tokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            NotificationCenter.default.removeObserver(token)
            DistributedNotificationCenter.default().removeObserver(token)
        }
        tokens.removeAll()
        started = false
    }

    func restore() {
        engine?.closeAll()
        updatePlayback()
        for screen in NSScreen.screens {
            guard let id = state.assignments[screen.wallpaperID], let item = wallpapers.first(where: { $0.id == id }) else { continue }
            engine?.apply(item, to: screen, paused: paused, speed: state.speed)
        }
    }

    func apply(_ item: Wallpaper) {
        checkpointPlaylistClocks()
        selection = item.id
        let screens = NSScreen.screens.filter { target == "all" || $0.wallpaperID == target }
        for screen in screens {
            state.assignments[screen.wallpaperID] = item.id
            if let entry = playlistEntry(for: item.id) {
                state.playlistPlayback[screen.wallpaperID] = PlaylistPlayback(entryID: entry.id, remainingSeconds: entry.duration.seconds)
            } else { state.playlistPlayback.removeValue(forKey: screen.wallpaperID) }
        }
        updatePlayback()
        for screen in screens {
            engine?.apply(item, to: screen, paused: paused, speed: state.speed)
        }
        save()
        syncLockScreen()
    }

    func stop() {
        if state.liveLockScreen { lockScreen.restore() }
        checkpointPlaylistClocks()
        state.assignments.removeAll()
        state.playlistPlayback.removeAll()
        engine?.closeAll()
        updatePlayback()
        save()
    }

    func togglePause() { state.manualPause.toggle(); updatePlayback(); save() }
    func updatePlayback() {
        // Stop probing when there is nothing to pause, or the display is asleep.
        let shouldMonitor = state.pauseInFullScreen && !state.assignments.isEmpty && !sleeping && !sessionLocked
            && !state.manualPause && !(state.pauseOnBattery && battery)
        if shouldMonitor {
            fullScreenActive = fullScreenProbe()
            if fullScreenTimer == nil {
                let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.updatePlayback() }
                }
                timer.tolerance = 0.5
                RunLoop.main.add(timer, forMode: .common)
                fullScreenTimer = timer
            }
        } else {
            fullScreenTimer?.invalidate()
            fullScreenTimer = nil
            fullScreenActive = false
        }
        engine?.setPaused(paused, speed: state.speed)
        if paused {
            if playlistTimer != nil { checkpointPlaylistClocks() }
        } else if playlistTimer == nil { schedulePlaylistTimer() }
    }
    func settingsChanged() { updatePlayback(); save(); syncLockScreen() }

    func syncLockScreen() {
        let screen = NSScreen.screens.first { $0 == NSScreen.main } ?? NSScreen.screens.first
        let id = screen.flatMap { state.assignments[$0.wallpaperID] } ?? state.assignments.sorted { $0.key < $1.key }.first?.value
        guard let item = wallpapers.first(where: { $0.id == id }) else { lockScreen.cancel(); return }
        lockScreen.request(item, enabled: state.liveLockScreen, onBattery: state.pauseOnBattery && battery, mainScreen: screen)
    }

    func restoreSystemWallpaper() {
        state.liveLockScreen = false
        save()
        lockScreen.restore()
    }

    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            if enabled && !loginEnabled { notice = "Approve OpenWall in System Settings → General → Login Items." }
        } catch { notice = "Login setting could not be changed: \(error.localizedDescription)" }
    }

    func chooseVideos() {
        let panel = NSOpenPanel()
        panel.title = "Import your video wallpapers"
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        importVideos(panel.urls)
    }

    func importVideos(_ urls: [URL]) {
        guard !importing else { return }
        importing = true
        Task {
            var errors: [String] = []
            for url in urls {
                do {
                    let imported = try await VideoImporter.importFile(url)
                    state.videos.append(Wallpaper(id: imported.id, name: imported.name, filename: imported.filename))
                    selection = imported.id
                    save()
                } catch { errors.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            }
            importing = false
            if !errors.isEmpty { notice = errors.joined(separator: "\n") }
        }
    }

    func remove(_ item: Wallpaper) {
        guard let filename = item.filename else { return }
        if let entry = playlistEntry(for: item.id) { removeFromPlaylist(entry.id) }
        state.assignments = state.assignments.filter { $0.value != item.id }
        state.videos.removeAll { $0.id == item.id }
        if selection == item.id { selection = "aurora" }
        restore()
        save()
        try? FileManager.default.removeItem(at: Storage.media.appendingPathComponent(filename))
        try? FileManager.default.removeItem(at: Storage.thumbnails.appendingPathComponent(item.id + ".jpg"))
    }
}
