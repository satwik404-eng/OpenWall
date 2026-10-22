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
        print("PASS: persisted media and settings round trip")
        print("PASS: old library migration preserves media/settings and enables fullscreen pause")
        var simulatedFullScreen = false
        let library = Library(fullScreenProbe: { simulatedFullScreen })
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
        library.apply(Wallpaper.presets[0])
        precondition(library.state.assignments[library.target] == "aurora")
        let old = library.state.assignments
        library.shuffle()
        precondition(library.state.assignments != old)
        print("PASS: per-display assignment, procedural wallpaper, shuffle")
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
