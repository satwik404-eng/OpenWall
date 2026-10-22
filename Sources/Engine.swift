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
}

struct MotionArtwork: View {
    let preset: String
    var animated = false

    static func colors(for preset: String) -> [Color] {
        switch preset {
        case "ember": return [Color(red: 0.12, green: 0.015, blue: 0.02), Color(red: 0.84, green: 0.13, blue: 0.045), Color(red: 1, green: 0.58, blue: 0.16)]
        case "amethyst": return [Color(red: 0.055, green: 0.015, blue: 0.14), Color(red: 0.42, green: 0.16, blue: 0.77), Color(red: 0.81, green: 0.56, blue: 1)]
        case "glacier": return [Color(red: 0.02, green: 0.10, blue: 0.17), Color(red: 0.19, green: 0.56, blue: 0.68), Color(red: 0.79, green: 0.96, blue: 0.98)]
        case "solar": return [Color(red: 0.17, green: 0.05, blue: 0.02), Color(red: 0.88, green: 0.40, blue: 0.08), Color(red: 1, green: 0.86, blue: 0.36)]
        case "midnight": return [Color(red: 0.025, green: 0.03, blue: 0.055), Color(red: 0.18, green: 0.22, blue: 0.34), Color(red: 0.57, green: 0.66, blue: 0.83)]
        case "rose": return [Color(red: 0.12, green: 0.025, blue: 0.09), Color(red: 0.69, green: 0.25, blue: 0.45), Color(red: 1, green: 0.68, blue: 0.75)]
        case "dusk": return [Color(red: 0.10, green: 0.025, blue: 0.14), Color(red: 0.97, green: 0.33, blue: 0.20), Color(red: 1, green: 0.70, blue: 0.37)]
        case "ocean": return [Color(red: 0.012, green: 0.04, blue: 0.15), Color(red: 0.06, green: 0.30, blue: 0.74), Color(red: 0.22, green: 0.83, blue: 0.92)]
        default: return [Color(red: 0.015, green: 0.07, blue: 0.085), Color(red: 0.05, green: 0.52, blue: 0.39), Color(red: 0.50, green: 0.91, blue: 0.60)]
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !animated)) { timeline in
            Canvas { context, size in
                let colors = Self.colors(for: preset)
                let time = animated ? timeline.date.timeIntervalSinceReferenceDate / 8 : 1.7
                let rect = CGRect(origin: .zero, size: size)
                context.fill(Path(rect), with: .linearGradient(Gradient(colors: [colors[0], colors[1].opacity(0.5), colors[0]]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
                for band in 0..<7 {
                    let n = Double(band)
                    var path = Path()
                    path.move(to: CGPoint(x: -size.width * 0.1, y: size.height * 1.2))
                    for step in 0...72 {
                        let x = Double(step) / 72 * size.width * 1.2 - size.width * 0.1
                        let wave = sin(x / size.width * 3.8 + time + n * 0.36) * size.height * 0.15
                        let y = size.height * (0.27 + n * 0.073) + wave
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                    path.addLine(to: CGPoint(x: size.width * 1.1, y: size.height * 1.2))
                    path.closeSubpath()
                    context.fill(path, with: .linearGradient(Gradient(colors: [colors[2].opacity(0.30), colors[1].opacity(0.13), colors[0].opacity(0.7)]), startPoint: CGPoint(x: size.width * 0.3, y: size.height * 0.25), endPoint: CGPoint(x: size.width * 0.6, y: size.height)))
                }
                // A deterministic star field; no files or external artwork required.
                for i in 0..<65 {
                    let x = Double((i * 137 + 17) % 997) / 997 * size.width
                    let y = Double((i * 79 + 43) % 631) / 631 * size.height * 0.57
                    let radius = i % 4 == 0 ? 1.25 : 0.65
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)), with: .color(.white.opacity(i % 3 == 0 ? 0.5 : 0.22)))
                }
            }
        }
        .clipped()
        .accessibilityLabel("\(preset) animated wallpaper")
    }
}
