import AppKit
import AVFoundation
import CoreVideo

@main struct IntegrationTests {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let display = FullScreenDetector.DisplayGeometry(bounds: CGRect(x: 0, y: 0, width: 1440, height: 900), topSafeArea: 0)
        func detects(_ bounds: CGRect, pid: pid_t = 42, layer: Int = 0, alpha: Double = 1,
                     displays: [FullScreenDetector.DisplayGeometry] = [display]) -> Bool {
            FullScreenDetector.detectsFullScreen(frontmostPID: 42,
                windows: [.init(ownerPID: pid, bounds: bounds, layer: layer, alpha: alpha)], displays: displays)
        }
        precondition(detects(display.bounds))
        precondition(!detects(CGRect(x: 0, y: 25, width: 1440, height: 800)))
        precondition(!detects(display.bounds, pid: 99))
        precondition(!detects(display.bounds, layer: -1))
        precondition(!detects(display.bounds, alpha: 0))
        let notched = FullScreenDetector.DisplayGeometry(bounds: display.bounds, topSafeArea: 38)
        precondition(detects(CGRect(x: 0, y: 38, width: 1440, height: 862), displays: [notched]))
        let above = FullScreenDetector.DisplayGeometry(bounds: CGRect(x: -1920, y: -1080, width: 1920, height: 1080), topSafeArea: 0)
        precondition(detects(above.bounds, displays: [display, above]))
        precondition(!detects(CGRect(x: -1910, y: -1070, width: 1800, height: 980), displays: [display, above]))
        print("PASS: fullscreen geometry, normal windows, other owners, wallpaper layers, transparent windows, notch and external-display coordinates")
        let testRoot = URL(fileURLWithPath: ProcessInfo.processInfo.environment["OPENWALL_DATA_DIR"]!)
        try FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
        let source = testRoot.appendingPathComponent("test-source.mov")
        try? FileManager.default.removeItem(at: source)
        let writer = try AVAssetWriter(outputURL: source, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 128, AVVideoHeightKey: 128])
        let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 128, kCVPixelBufferHeightKey as String: 128])
        writer.add(input)
        precondition(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<30 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(10)) }
            var buffer: CVPixelBuffer?
            precondition(CVPixelBufferCreate(kCFAllocatorDefault, 128, 128, kCVPixelFormatType_32ARGB, nil, &buffer) == kCVReturnSuccess)
            CVPixelBufferLockBaseAddress(buffer!, [])
            memset(CVPixelBufferGetBaseAddress(buffer!), Int32(30 + frame * 4), CVPixelBufferGetDataSize(buffer!))
            CVPixelBufferUnlockBaseAddress(buffer!, [])
            precondition(adapter.append(buffer!, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        precondition(writer.status == .completed)
        print("PASS: generated a real one-second H.264 test video")
        let imported = try await VideoImporter.importFile(source)
        precondition(FileManager.default.fileExists(atPath: Storage.media.appendingPathComponent(imported.filename).path))
        precondition(FileManager.default.fileExists(atPath: Storage.thumbnails.appendingPathComponent(imported.id + ".jpg").path))
        print("PASS: imported video, copied media, generated thumbnail")
        let invalid = testRoot.appendingPathComponent("invalid.mp4")
        try Data("not video".utf8).write(to: invalid)
        do { _ = try await VideoImporter.importFile(invalid); fatalError("Invalid video accepted") }
        catch { print("PASS: rejected invalid video") }
        let item = Wallpaper(id: imported.id, name: imported.name, filename: imported.filename)
        var saved = LibraryState()
        saved.videos = [item]; saved.pauseOnBattery = false
        saved.speed = 1.5; saved.manualPause = true
        saved.pauseInFullScreen = false
        try Storage.save(saved)
        let loaded = try Storage.load()
        precondition(loaded.videos == [item] && loaded.speed == 1.5 && loaded.manualPause)
        precondition(!loaded.pauseInFullScreen)
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as! [String: Any]
        legacy.removeValue(forKey: "pauseInFullScreen")
        let migrated = try JSONDecoder().decode(LibraryState.self, from: JSONSerialization.data(withJSONObject: legacy))
        precondition(migrated.pauseInFullScreen && migrated.videos == saved.videos && migrated.manualPause)
        legacy.removeValue(forKey: "playlist")
        legacy.removeValue(forKey: "playlistPlayback")
        legacy["shuffleMinutes"] = 5
        legacy["assignments"] = ["legacy-display": item.id]
        let oldShuffle = try JSONDecoder().decode(LibraryState.self, from: JSONSerialization.data(withJSONObject: legacy))
        precondition(oldShuffle.playlist.count == Wallpaper.presets.count + 1 && oldShuffle.playlist.allSatisfy { $0.duration == .fiveMinutes })
        precondition(oldShuffle.playlistPlayback["legacy-display"]?.remainingSeconds == 300)
        precondition(!migrated.liveLockScreen)
        let poster = try await LockScreenRenderer.poster(for: Wallpaper.presets[0])
        let otherPoster = try await LockScreenRenderer.poster(for: Wallpaper.presets[1])
        let firstImage = NSImage(contentsOf: poster)!
        precondition(firstImage.size.width == 1920 && firstImage.size.height == 1080)
        let posterData = try Data(contentsOf: poster), otherPosterData = try Data(contentsOf: otherPoster)
        precondition(posterData != otherPosterData)
        let videoPoster = try await LockScreenRenderer.poster(for: item)
        precondition(FileManager.default.fileExists(atPath: videoPoster.path))
        let nativeMovie = testRoot.appendingPathComponent("native-test.mov")
        try await NativeMovieEncoder.transcode(source, to: nativeMovie)
        let nativeAsset = AVURLAsset(url: nativeMovie)
        let nativeTracks = try await nativeAsset.loadTracks(withMediaType: .video)
        let formats = try await nativeTracks[0].load(.formatDescriptions)
        precondition(CMFormatDescriptionGetMediaSubType(formats[0]) == kCMVideoCodecType_HEVC)
        let nativeAudio = try await nativeAsset.loadTracks(withMediaType: .audio)
        precondition(nativeAudio.isEmpty)
        let nativeFrame = try await AVAssetImageGenerator(asset: nativeAsset).image(at: .zero)
        precondition(nativeFrame.image.width > 0)
        let originalManifest: [String: Any] = ["categories": [["id": "apple"]], "assets": [["id": "apple-video"]], "version": 7]
        let manifest = try NativeLockScreenStore.manifestByAdding(JSONSerialization.data(withJSONObject: originalManifest), id: "test-native-id", name: "Test wallpaper", movie: nativeMovie, poster: videoPoster)
        let nativeManifest = try JSONSerialization.jsonObject(with: manifest) as! [String: Any]
        precondition((nativeManifest["assets"] as! [[String: Any]]).contains { $0["id"] as? String == "apple-video" })
        precondition(nativeManifest["version"] as? Int == 7)
        let fixture: [String: Any] = ["SystemDefault": ["Type": "individual", "Desktop": ["Content": ["EncodedOptionValues": Data([1,2,3])]]], "Spaces": ["space-1": ["Default": ["Type": "individual"], "Keep": "metadata", "Displays": ["display-1": ["Type": "individual"]]]], "Unknown": "preserved"]
        let nativeIndex = try NativeLockScreenStore.linkedIndex(PropertyListSerialization.data(fromPropertyList: fixture, format: .binary, options: 0), id: "test-native-id")
        let nativePlist = try PropertyListSerialization.propertyList(from: nativeIndex, format: nil) as! [String: Any]
        precondition(nativePlist["Unknown"] as? String == "preserved")
        let spaces = nativePlist["Spaces"] as! [String: [String: Any]]
        precondition(spaces["space-1"]?["Keep"] as? String == "metadata")
        let linked = (nativePlist["SystemDefault"] as! [String: Any])["Linked"] as! [String: Any]
        let choices = (linked["Content"] as! [String: Any])["Choices"] as! [[String: Any]]
        let nativeConfig = try PropertyListSerialization.propertyList(from: choices[0]["Configuration"] as! Data, format: nil) as! [String: String]
        precondition(nativeConfig["assetID"] == "test-native-id")
        let saverURL = URL(fileURLWithPath: "/tmp/OpenWall.saver")
        let saverIndex = try NativeLockScreenStore.keepingScreenSaver(nativeIndex, module: saverURL)
        let saverPlist = try PropertyListSerialization.propertyList(from: saverIndex, format: nil) as! [String: Any]
        let saverContainer = saverPlist["AllSpacesAndDisplays"] as! [String: Any]
        precondition(saverContainer["Type"] as? String == "individual" && saverContainer["Desktop"] != nil)
        let saverIdle = saverContainer["Idle"] as! [String: Any]
        let saverChoice = ((saverIdle["Content"] as! [String: Any])["Choices"] as! [[String: Any]])[0]
        precondition(saverChoice["Provider"] as? String == "com.apple.wallpaper.choice.screen-saver")
        let saverConfig = try PropertyListSerialization.propertyList(from: saverChoice["Configuration"] as! Data, format: nil) as! [String: Any]
        precondition((saverConfig["module"] as! [String: String])["relative"] == saverURL.absoluteString)
        print("PASS: live wallpaper sync keeps the installed OpenWall screen saver selected instead of replacing it with an Apple aerial")
        let stillIndex = try StoppedWallpaperStore.replacingDesktop(nativeIndex, frames: ["display-1": videoPoster], defaultFrame: videoPoster)
        let stillPlist = try PropertyListSerialization.propertyList(from: stillIndex, format: nil) as! [String: Any]
        let stillContainer = stillPlist["AllSpacesAndDisplays"] as! [String: Any]
        precondition(stillContainer["Type"] as? String == "individual" && stillContainer["Linked"] == nil)
        let stillDesktop = stillContainer["Desktop"] as! [String: Any]
        let stillChoice = ((stillDesktop["Content"] as! [String: Any])["Choices"] as! [[String: Any]])[0]
        let stillConfig = try PropertyListSerialization.propertyList(from: stillChoice["Configuration"] as! Data, format: nil) as! [String: Any]
        precondition((stillConfig["url"] as! [String: String])["relative"] == videoPoster.absoluteString)
        let retainedIdle = stillContainer["Idle"] as! [String: Any]
        let retainedChoice = ((retainedIdle["Content"] as! [String: Any])["Choices"] as! [[String: Any]])[0]
        precondition(retainedChoice["Provider"] as? String == "com.apple.wallpaper.choice.aerials")
        let retainedSpaces = stillPlist["Spaces"] as! [String: [String: Any]]
        precondition(retainedSpaces["space-1"]?["Keep"] as? String == "metadata" && stillPlist["Unknown"] as? String == "preserved")
        print("PASS: quit-to-still splits native desktop from aerial Idle, preserving lock-screen choice, display/Space identities and metadata")
        print("PASS: matching full-resolution preset/video thumbnails, real HEVC transcode/decode, native manifest preserves Apple entries, linked configuration preserves Space metadata")
        print("PASS: persisted media and settings round trip")
        print("PASS: old library migration preserves media/settings and enables fullscreen pause")
        var simulatedFullScreen = false
        var simulatedTime: TimeInterval = 1000
        let library = Library(fullScreenProbe: { simulatedFullScreen }, clock: { simulatedTime })
        library.start()
        precondition(!library.displays.isEmpty)
        library.state.manualPause = false
        library.state.speed = 1.0
        library.state.pauseInFullScreen = true
        library.apply(item)
        precondition(library.engine!.count == NSScreen.screens.count)
        precondition(library.engine!.allIgnoreMouse && library.engine!.allBelowIcons)
        try await Task.sleep(for: .seconds(3))
        let player = library.engine!.activePlayer!
        precondition(player.error == nil && player.rate == 1)
        precondition(player.currentTime().seconds > 0)
        print("PASS: real video playback and looping beyond source duration; desktop windows below icons ignore clicks")
        library.togglePause()
        precondition(player.rate == 0 && library.paused)
        library.togglePause()
        precondition(player.rate == 1 && !library.paused)
        print("PASS: manual pause and resume")
        simulatedFullScreen = true; library.updatePlayback()
        precondition(player.rate == 0 && library.paused && library.status == "Paused in full screen")
        let assignments = library.state.assignments
        try await Task.sleep(for: .milliseconds(300))
        precondition(library.state.assignments == assignments)
        simulatedFullScreen = false; library.updatePlayback()
        precondition(player.rate == 1 && !library.paused)
        simulatedFullScreen = true; library.updatePlayback()
        library.togglePause()
        simulatedFullScreen = false; library.updatePlayback()
        precondition(player.rate == 0 && library.state.manualPause)
        library.togglePause(); precondition(player.rate == 1)
        simulatedFullScreen = true; library.updatePlayback()
        library.state.pauseInFullScreen = false; library.settingsChanged()
        precondition(player.rate == 1 && !library.paused)
        library.state.pauseInFullScreen = true; library.settingsChanged()
        precondition(player.rate == 0)
        library.state.pauseOnBattery = true; library.battery = true; library.updatePlayback()
        simulatedFullScreen = false; library.updatePlayback()
        precondition(player.rate == 0 && library.status == "Paused on battery")
        library.battery = false; library.updatePlayback(); precondition(player.rate == 1)
        print("PASS: fullscreen pauses real AVPlayer; exit resumes; manual/battery pause stays respected; fullscreen toggle applies immediately")
        library.state.pauseOnBattery = true; library.battery = true
        library.updatePlayback(); precondition(player.rate == 0)
        library.battery = false; library.updatePlayback(); precondition(player.rate == 1)
        library.sleeping = true; library.updatePlayback(); precondition(player.rate == 0)
        library.sleeping = false; library.updatePlayback(); precondition(player.rate == 1)
        print("PASS: simulated battery and display-sleep state pause/resume")
        library.target = library.displays[0].id
        let screenID = library.target
        precondition(WallpaperDuration.allCases.map(\.rawValue) == [86400, 21600, 10800, 3600, 1800, 300, 0])
        precondition(Wallpaper.presets.count == 89 && Set(Wallpaper.presets.map(\.id)).count == 89)
        Wallpaper.presets.prefix(3).forEach { library.addToPlaylist($0) }
        library.addToPlaylist(Wallpaper.presets[0])
        precondition(library.state.playlist.count == 3)
        let first = library.state.playlist[0].id
        let second = library.state.playlist[1].id
        let third = library.state.playlist[2].id
        library.setDuration(.fiveMinutes, for: first)
        library.setDuration(.sixHours, for: second)
        library.setDuration(.forever, for: third)
        library.apply(Wallpaper.presets[0])
        precondition(library.state.assignments[screenID] == "aurora" && library.selection == "aurora")
        simulatedTime += 299; library.advanceDuePlaylist()
        precondition(library.state.assignments[screenID] == "aurora")
        simulatedTime += 1; library.advanceDuePlaylist()
        precondition(library.state.assignments[screenID] == "dusk")
        precondition(library.remainingPlaylistTime(on: screenID) == 21600)
        for duration in WallpaperDuration.allCases {
            library.setDuration(duration, for: second)
            precondition(library.remainingPlaylistTime(on: screenID) == duration.seconds)
        }
        simulatedTime += 172800; library.advanceDuePlaylist()
        precondition(library.state.assignments[screenID] == "dusk" && library.playlistTimer == nil)
        library.nextInPlaylist(); precondition(library.state.assignments[screenID] == "ocean")
        library.nextInPlaylist(); precondition(library.state.assignments[screenID] == "aurora")
        print("PASS: all seven durations, exact expiry, ordered advance, Forever hold, manual skip, wraparound, duplicate prevention and immediate apply")
        library.apply(Wallpaper.presets[0])
        library.checkpointPlaylistClocks()
        library.state.playlistPlayback[screenID]?.remainingSeconds = 0
        library.schedulePlaylistTimer()
        try await Task.sleep(for: .milliseconds(200))
        precondition(library.state.assignments[screenID] == "dusk")
        library.apply(Wallpaper.presets[0])
        print("PASS: a real Foundation timer fires and advances the desktop wallpaper")
        simulatedTime += 90; library.togglePause()
        precondition(library.remainingPlaylistTime(on: screenID) == 210)
        simulatedTime += 10000; library.advanceDuePlaylist()
        precondition(library.remainingPlaylistTime(on: screenID) == 210)
        library.togglePause()
        simulatedTime += 209; library.advanceDuePlaylist()
        precondition(library.state.assignments[screenID] == "aurora")
        simulatedTime += 1; library.advanceDuePlaylist()
        precondition(library.state.assignments[screenID] == "dusk")
        library.apply(Wallpaper.presets[0])
        simulatedTime += 20; simulatedFullScreen = true; library.updatePlayback()
        simulatedTime += 10000; library.advanceDuePlaylist()
        precondition(library.remainingPlaylistTime(on: screenID) == 280)
        simulatedFullScreen = false; library.updatePlayback()
        library.battery = true; library.updatePlayback()
        simulatedTime += 10000; library.advanceDuePlaylist()
        precondition(library.remainingPlaylistTime(on: screenID) == 280)
        library.battery = false; library.updatePlayback()
        library.sleeping = true; library.updatePlayback()
        simulatedTime += 10000; library.advanceDuePlaylist()
        precondition(library.remainingPlaylistTime(on: screenID) == 280)
        library.sleeping = false; library.updatePlayback()
        print("PASS: playlist countdown freezes for manual, fullscreen, battery and sleep pauses, and resumes with remaining time")
        let existingTimer = library.playlistTimer
        library.updatePlayback()
        precondition(library.playlistTimer === existingTimer)
        library.movePlaylistEntry(third, by: -1)
        precondition(library.state.playlist.map(\.id) == [first, third, second])
        simulatedTime += 280; library.advanceDuePlaylist()
        precondition(library.state.assignments[screenID] == "ocean")
        library.removeFromPlaylist(third)
        precondition(library.state.assignments[screenID] == "dusk")
        library.apply(Wallpaper.presets[0])
        simulatedTime += 30
        library.shutdown()
        let persisted = Library(fullScreenProbe: { false }, clock: { simulatedTime })
        precondition(persisted.state.playlist == library.state.playlist)
        precondition(persisted.state.playlistPlayback[screenID]?.remainingSeconds == 270)
        print("PASS: reordering, removing active entry advances, no timer churn on status checks, and countdown persists on quit")
        // Resume the test model after checkpointing; no real elapsed time is required.
        library.restore()
        library.state.playlistPlayback["disconnected-display"] = PlaylistPlayback(entryID: first, remainingSeconds: 123)
        library.apply(item)
        precondition(library.state.assignments[screenID] == item.id && library.state.playlistPlayback[screenID] == nil)
        precondition(library.state.playlistPlayback["disconnected-display"]?.remainingSeconds == 123)
        library.apply(Wallpaper.presets[0]); library.stopPlaylist()
        precondition(library.state.playlistPlayback[screenID] == nil && library.state.assignments[screenID] == "aurora")
        print("PASS: manual wallpaper outside playlist stops only targeted rotation; stop playlist keeps wallpaper; disconnected display state is retained")
        let freezeRoot = testRoot.appendingPathComponent("StoppedFrames")
        library.apply(item)
        try await Task.sleep(for: .milliseconds(240))
        let videoFrames = await library.engine!.captureStillFrames(in: freezeRoot) { _ in nil }
        precondition(videoFrames.count == 1 && NSImage(contentsOf: videoFrames[screenID]!) != nil)
        precondition(library.engine!.activePlayer?.rate == 0)
        library.apply(Wallpaper.presets[0])
        let motionFrames = await library.engine!.captureStillFrames(in: freezeRoot) { videoFrames[$0] }
        precondition(motionFrames.count == 1 && NSImage(contentsOf: motionFrames[screenID]!) != nil)
        precondition(motionFrames[screenID] != videoFrames[screenID])
        _ = await library.engine!.captureStillFrames(in: freezeRoot) { motionFrames[$0] }
        let stoppedFiles = try FileManager.default.contentsOfDirectory(atPath: freezeRoot.path)
        precondition(stoppedFiles.count == 2)
        print("PASS: quit captures the playing video's current frame and motion artwork, pauses decoding, and retains only two stills per display")
        library.stop()
        precondition(library.engine!.count == 0 && library.state.assignments.isEmpty)
        library.remove(item)
        precondition(library.state.videos.isEmpty)
        precondition(!FileManager.default.fileExists(atPath: Storage.media.appendingPathComponent(imported.filename).path))
        precondition(FileManager.default.fileExists(atPath: source.path))
        print("PASS: stop closes windows; remove deletes imported copy and preserves original")
        print("ALL INTEGRATION CHECKS PASSED on \(NSScreen.screens.count) connected display(s)")
    }
}
