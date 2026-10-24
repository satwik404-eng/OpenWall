import ScreenSaver
import AppKit
import AVFoundation
import QuartzCore
import IOKit.ps

/// Runs in the OS screen-saver host. Reads only OpenWall's own local cache.
@objc(OpenWallSaverView)
final class OpenWallSaverView: ScreenSaverView {
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var videoLayer: AVPlayerLayer?
    private var motionPreset: String?
    private var motionPaused = false
    override var isFlipped: Bool { true }

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        animationTimeInterval = 1
    }
    required init?(coder: NSCoder) { super.init(coder: coder); wantsLayer = true }
    override func startAnimation() {
        super.startAnimation()
        clear()
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("org.openwall.desktop")
        let state = (try? JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("library.json")))) as? [String: Any] ?? [:]
        let assignments = state["assignments"] as? [String: String] ?? [:]
        let screenID = (window?.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue
        let id = screenID.flatMap { assignments[$0] } ?? assignments.sorted { $0.key < $1.key }.first?.value ?? "aurora"
        let video = (state["videos"] as? [[String: Any]])?.first { $0["id"] as? String == id }
        var pauseOnBattery = false
        if state["pauseOnBattery"] as? Bool ?? true,
           let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() {
            pauseOnBattery = (type as String) == kIOPSBatteryPowerValue
        }
        if let filename = video?["filename"] as? String, filename == (filename as NSString).lastPathComponent {
            if pauseOnBattery,
               let thumbnail = NSImage(contentsOf: root.appendingPathComponent("Thumbnails").appendingPathComponent(id + ".jpg")) {
                let poster = AVPlayerLayer()
                poster.contents = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil)
                poster.contentsGravity = .resizeAspectFill; poster.frame = bounds
                layer?.addSublayer(poster); videoLayer = poster
                return
            }
            let url = root.appendingPathComponent("Media").appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: url.path) {
                let queue = AVQueuePlayer()
                queue.isMuted = true
                queue.preventsDisplaySleepDuringVideoPlayback = false
                looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))
                player = queue
                let surface = AVPlayerLayer(player: queue)
                surface.videoGravity = .resizeAspectFill; surface.frame = bounds
                layer?.addSublayer(surface); videoLayer = surface
                // On battery, decode one still frame and leave the player paused.
                if pauseOnBattery { queue.seek(to: .zero) }
                else { queue.playImmediately(atRate: Float(state["speed"] as? Double ?? 1)) }
                return
            }
        }
        motionPreset = id
        motionPaused = pauseOnBattery
        animationTimeInterval = pauseOnBattery ? 1 : 1.0 / 24
        needsDisplay = true
    }
    override func animateOneFrame() {
        if motionPreset != nil && !motionPaused { needsDisplay = true }
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let preset = motionPreset, let context = NSGraphicsContext.current?.cgContext else { return }
        MotionCGRenderer.draw(preset, time: motionPaused ? 1.7 : Date.timeIntervalSinceReferenceDate / 8, size: bounds.size, in: context)
    }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        videoLayer?.frame = bounds
        needsDisplay = true
        CATransaction.commit()
    }
    private func clear() {
        player?.pause(); looper?.disableLooping()
        videoLayer?.removeFromSuperlayer()
        player = nil; looper = nil; videoLayer = nil; motionPreset = nil
    }
    override func stopAnimation() { clear(); super.stopAnimation() }
}
