import AppKit

enum WallpaperDuration: Int, Codable, CaseIterable, Identifiable {
    case oneDay = 86400, sixHours = 21600, threeHours = 10800, oneHour = 3600
    case thirtyMinutes = 1800, fiveMinutes = 300, forever = 0
    var id: Int { rawValue }
    var seconds: TimeInterval? { self == .forever ? nil : Double(rawValue) }
    var title: String {
        switch self {
        case .oneDay: return "1 day"
        case .sixHours: return "6 hours"
        case .threeHours: return "3 hours"
        case .oneHour: return "1 hour"
        case .thirtyMinutes: return "30 minutes"
        case .fiveMinutes: return "5 minutes"
        case .forever: return "Forever"
        }
    }
}

struct PlaylistEntry: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    let wallpaperID: String
    var duration: WallpaperDuration = .oneHour
}

struct PlaylistPlayback: Codable, Equatable {
    var entryID: String
    var remainingSeconds: TimeInterval?
}

@MainActor extension Library {
    var hasPlaylistPlayback: Bool { !state.playlistPlayback.isEmpty }

    func playlistEntry(for wallpaperID: String) -> PlaylistEntry? {
        state.playlist.first { $0.wallpaperID == wallpaperID }
    }

    func addToPlaylist(_ item: Wallpaper) {
        guard playlistEntry(for: item.id) == nil else { return }
        state.playlist.append(PlaylistEntry(wallpaperID: item.id))
        save()
    }

    func setDuration(_ duration: WallpaperDuration, for entryID: String) {
        guard let index = state.playlist.firstIndex(where: { $0.id == entryID }) else { return }
        checkpointPlaylistClocks()
        state.playlist[index].duration = duration
        for screenID in Array(state.playlistPlayback.keys) where state.playlistPlayback[screenID]?.entryID == entryID {
            state.playlistPlayback[screenID]?.remainingSeconds = duration.seconds
        }
        updatePlayback()
        save()
    }

    func movePlaylistEntry(_ entryID: String, by offset: Int) {
        guard let index = state.playlist.firstIndex(where: { $0.id == entryID }) else { return }
        let destination = index + offset
        guard state.playlist.indices.contains(destination) else { return }
        checkpointPlaylistClocks()
        let entry = state.playlist.remove(at: index)
        state.playlist.insert(entry, at: destination)
        schedulePlaylistTimer()
        save()
    }

    func removeFromPlaylist(_ entryID: String) {
        guard let index = state.playlist.firstIndex(where: { $0.id == entryID }) else { return }
        checkpointPlaylistClocks()
        let affected = state.playlistPlayback.filter { $0.value.entryID == entryID }.map(\.key)
        state.playlist.remove(at: index)
        for screenID in affected {
            if state.playlist.isEmpty { state.playlistPlayback.removeValue(forKey: screenID) }
            else { playEntry(state.playlist[index % state.playlist.count], on: screenID) }
        }
        schedulePlaylistTimer()
        save()
    }

    func startPlaylist() {
        guard let entry = playlistEntry(for: selection) ?? state.playlist.first,
              let item = wallpapers.first(where: { $0.id == entry.wallpaperID }) else { return }
        apply(item)
    }

    func stopPlaylist() {
        checkpointPlaylistClocks()
        for display in displays where target == "all" || display.id == target {
            state.playlistPlayback.removeValue(forKey: display.id)
        }
        schedulePlaylistTimer()
        save()
    }

    func nextInPlaylist() {
        checkpointPlaylistClocks()
        for display in displays where target == "all" || display.id == target {
            guard let progress = state.playlistPlayback[display.id] else { continue }
            advancePlaylist(on: display.id, after: progress.entryID)
        }
        schedulePlaylistTimer()
        save()
    }

    func checkpointPlaylistClocks() {
        playlistTimer?.invalidate()
        playlistTimer = nil
        let now = clock()
        for (screenID, resumedAt) in playlistAnchors {
            guard let remaining = state.playlistPlayback[screenID]?.remainingSeconds else { continue }
            state.playlistPlayback[screenID]?.remainingSeconds = max(0, remaining - max(0, now - resumedAt))
        }
        playlistAnchors.removeAll()
    }

    func schedulePlaylistTimer() {
        playlistTimer?.invalidate()
        playlistTimer = nil
        playlistAnchors.removeAll()
        guard !paused else { return }
        let connected = Set(displays.map(\.id))
        let now = clock()
        var nextDeadline: TimeInterval?
        for (screenID, progress) in state.playlistPlayback where connected.contains(screenID) {
            guard let remaining = progress.remainingSeconds else { continue }
            playlistAnchors[screenID] = now
            nextDeadline = min(nextDeadline ?? remaining, remaining)
        }
        guard let delay = nextDeadline else { return }
        let timer = Timer(timeInterval: max(0.05, delay), repeats: false) { [weak self] _ in
            Task { @MainActor in self?.advanceDuePlaylist() }
        }
        timer.tolerance = min(1, max(0.01, delay * 0.01))
        RunLoop.main.add(timer, forMode: .common)
        playlistTimer = timer
    }

    func advanceDuePlaylist() {
        checkpointPlaylistClocks()
        if !paused {
            let connected = Set(displays.map(\.id))
            let due = state.playlistPlayback.filter { connected.contains($0.key) && ($0.value.remainingSeconds.map { $0 <= 0 } ?? false) }
            for (screenID, progress) in due { advancePlaylist(on: screenID, after: progress.entryID) }
        }
        schedulePlaylistTimer()
        save()
    }

    private func advancePlaylist(on screenID: String, after entryID: String) {
        guard let index = state.playlist.firstIndex(where: { $0.id == entryID }), !state.playlist.isEmpty else {
            state.playlistPlayback.removeValue(forKey: screenID)
            return
        }
        playEntry(state.playlist[(index + 1) % state.playlist.count], on: screenID)
    }

    private func playEntry(_ entry: PlaylistEntry, on screenID: String) {
        guard let item = wallpapers.first(where: { $0.id == entry.wallpaperID }) else {
            state.playlistPlayback.removeValue(forKey: screenID)
            return
        }
        state.assignments[screenID] = item.id
        state.playlistPlayback[screenID] = PlaylistPlayback(entryID: entry.id, remainingSeconds: entry.duration.seconds)
        selection = item.id
        if let screen = NSScreen.screens.first(where: { $0.wallpaperID == screenID }) {
            engine?.apply(item, to: screen, paused: paused, speed: state.speed)
        }
        syncLockScreen()
    }

    func remainingPlaylistTime(on screenID: String) -> TimeInterval? {
        guard let remaining = state.playlistPlayback[screenID]?.remainingSeconds else { return nil }
        let elapsed = playlistAnchors[screenID].map { max(0, clock() - $0) } ?? 0
        return max(0, remaining - elapsed)
    }

    func freezeDesktopForQuit() async {
        lockScreen.cancel()
        checkpointPlaylistClocks()
        stopMonitoring()
        playlistTimer?.invalidate()
        playlistTimer = nil
        save()
        let screens = Dictionary(uniqueKeysWithValues: NSScreen.screens.map { ($0.wallpaperID, $0) })
        let capture = Task { @MainActor in
            await engine?.captureStillFrames(in: Storage.root.appendingPathComponent("StoppedFrames")) { _ in nil } ?? [:]
        }
        let deadline = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(5)); capture.cancel() } catch { }
        }
        let frames = await capture.value
        deadline.cancel()
        if FileManager.default.fileExists(atPath: StoppedWallpaperStore.index.path) {
            do { try StoppedWallpaperStore.install(frames, screens: screens); return }
            catch { notice = "The native still handoff failed: " + error.localizedDescription }
        }
        for (id, url) in frames {
            guard let screen = screens[id] else { continue }
            do {
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen,
                    options: [.imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue, .allowClipping: true])
            } catch { notice = "Could not leave a still wallpaper: " + error.localizedDescription }
        }
    }

    func shutdown() {
        lockScreen.cancel()
        checkpointPlaylistClocks()
        stopMonitoring()
        playlistTimer?.invalidate()
        playlistTimer = nil
        save()
        engine?.closeAll()
    }
}
