import AppKit
import AVFoundation
import SwiftUI
import IOKit.ps

extension NSScreen {
    var wallpaperID: String {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? localizedName
    }
}

enum Power {
    static var isOnBattery: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        return (type as String) == kIOPSBatteryPowerValue
    }
}

final class DesktopWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class PlayerSurface: NSView {
    let playerLayer = AVPlayerLayer()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(playerLayer)
        playerLayer.videoGravity = .resizeAspectFill
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() { super.layout(); playerLayer.frame = bounds }
}

@MainActor
final class WallpaperSession {
    let window: DesktopWindow
    var player: AVQueuePlayer?
    var looper: AVPlayerLooper?
    var observation: NSKeyValueObservation?
    let item: Wallpaper
    private var playbackPaused: Bool
    private var playbackSpeed: Double

    init(item: Wallpaper, screen: NSScreen, paused: Bool, speed: Double, onError: @escaping (String) -> Void) {
        self.item = item
        playbackPaused = paused
        playbackSpeed = speed
        window = DesktopWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
        window.setFrame(screen.frame, display: false)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.title = "OpenWall Desktop — \(item.name)"
        if let filename = item.filename {
            let surface = PlayerSurface(frame: NSRect(origin: .zero, size: screen.frame.size))
            let player = AVQueuePlayer()
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            let template = AVPlayerItem(url: Storage.media.appendingPathComponent(filename))
            looper = AVPlayerLooper(player: player, templateItem: template)
            self.player = player
            surface.playerLayer.player = player
            window.contentView = surface
            observation = looper?.observe(\.status, options: [.new]) { looper, _ in
                if looper.status == .failed {
                    let message = looper.error?.localizedDescription ?? "The video could not be played."
                    Task { @MainActor in onError("\(item.name): \(message)") }
                }
            }
            if !paused { player.playImmediately(atRate: Float(speed)) }
        } else {
            window.contentView = NSHostingView(rootView: MotionArtwork(preset: item.id, animated: !paused))
        }
        window.orderFrontRegardless()
    }

    func setPaused(_ paused: Bool, speed: Double) {
        // Status checks must not restart AVPlayer or rebuild the animation host.
        guard paused != playbackPaused || speed != playbackSpeed else { return }
        playbackPaused = paused
        playbackSpeed = speed
        if let player {
            if paused { player.pause() }
            else { player.playImmediately(atRate: Float(speed)) }
        } else if let host = window.contentView as? NSHostingView<MotionArtwork> {
            host.rootView = MotionArtwork(preset: item.id, animated: !paused)
        }
    }

    func close() { observation = nil; player?.pause(); looper?.disableLooping(); window.close() }

    func freezeFrame() async throws -> CGImage {
        if let player, let asset = player.currentItem?.asset {
            let time = player.currentTime()
            player.pause()
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 2560, height: 2560)
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            return try await withTaskCancellationHandler {
                try await generator.image(at: time.isNumeric ? time : .zero).image
            } onCancel: { generator.cancelAllCGImageGeneration() }
        }
        let time = playbackPaused ? 1.7 : Date.timeIntervalSinceReferenceDate / 8
        if let host = window.contentView as? NSHostingView<MotionArtwork> {
            host.rootView = MotionArtwork(preset: item.id, fixedTime: time)
        }
        let size = window.frame.size
        let scale = min(1, 2560 / max(size.width, size.height))
        return try LockScreenRenderer.motionFrame(item.id, time: time,
            width: max(1, Int(size.width * scale)), height: max(1, Int(size.height * scale)))
    }
}

@MainActor
final class WallpaperEngine {
    private var sessions: [String: WallpaperSession] = [:]
    var onError: ((String) -> Void)?

    func apply(_ item: Wallpaper, to screen: NSScreen, paused: Bool, speed: Double) {
        if let filename = item.filename,
           !FileManager.default.fileExists(atPath: Storage.media.appendingPathComponent(filename).path) {
            onError?("\(item.name) is missing from the local library. Import the video again.")
            return
        }
        sessions.removeValue(forKey: screen.wallpaperID)?.close()
        sessions[screen.wallpaperID] = WallpaperSession(item: item, screen: screen, paused: paused, speed: speed) { [weak self] in self?.onError?($0) }
    }
    func setPaused(_ paused: Bool, speed: Double) { sessions.values.forEach { $0.setPaused(paused, speed: speed) } }
    func closeAll() { sessions.values.forEach { $0.close() }; sessions.removeAll() }
    func reorder() { sessions.values.forEach { $0.window.orderFrontRegardless() } }
    var count: Int { sessions.count }
    var allIgnoreMouse: Bool { sessions.values.allSatisfy { $0.window.ignoresMouseEvents && !$0.window.canBecomeKey } }
    var allBelowIcons: Bool { sessions.values.allSatisfy { $0.window.level.rawValue < Int(CGWindowLevelForKey(.desktopIconWindow)) } }
    var activePlayer: AVQueuePlayer? { sessions.values.compactMap(\.player).first }

    // Two alternating files per display prevent macOS reusing a cached URL.
    // These are rendered from our own media, without screen-recording access.
    func captureStillFrames(in root: URL, currentImage: (String) -> URL?) async -> [String: URL] {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var result: [String: URL] = [:]
        for (id, session) in sessions {
            guard !Task.isCancelled else { break }
            let safeID = String(id.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
            let first = root.appendingPathComponent(safeID + "-0.jpg")
            let second = root.appendingPathComponent(safeID + "-1.jpg")
            let current = currentImage(id)
            let firstDate = (try? first.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let secondDate = (try? second.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let next = current == first ? second : current == second ? first : firstDate > secondDate ? second : first
            do {
                let image = try await session.freezeFrame()
                guard let jpeg = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else { continue }
                try jpeg.write(to: next, options: .atomic)
                result[id] = next
            } catch { onError?("Could not save the stopped wallpaper: " + error.localizedDescription) }
        }
        return result
    }
}
