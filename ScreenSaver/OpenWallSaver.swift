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
    private var motionLayer: CAGradientLayer?

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
        let palettes: [String: [UInt32]] = [
            "aurora": [0x041216, 0x0d8563, 0x80e899], "dusk": [0x1a0624, 0xf75433, 0xffb25e],
            "ocean": [0x030a26, 0x0f4cbd, 0x38d4eb], "ember": [0x1f0405, 0xd6210b, 0xff9429],
            "amethyst": [0x0e0424, 0x6b29c4, 0xcf8fff], "glacier": [0x051a2b, 0x308fad, 0xc9f5fa],
            "solar": [0x2b0d05, 0xe06614, 0xffdb5c], "midnight": [0x06080e, 0x2e3857, 0x91a8d4],
            "rose": [0x1f0617, 0xb04073, 0xffadbf]]
        let colors = (palettes[id] ?? palettes["aurora"]!).map { n in
            NSColor(srgbRed: CGFloat((n >> 16) & 255) / 255, green: CGFloat((n >> 8) & 255) / 255, blue: CGFloat(n & 255) / 255, alpha: 1).cgColor
        }
        let gradient = CAGradientLayer()
        gradient.frame = bounds.insetBy(dx: -bounds.width / 2, dy: -bounds.height / 2)
        gradient.colors = colors + [colors[0]]; gradient.locations = [0, 0.35, 0.7, 1]
        gradient.startPoint = CGPoint(x: 0.05, y: 0.1); gradient.endPoint = CGPoint(x: 0.9, y: 0.85)
        layer?.addSublayer(gradient); motionLayer = gradient
        if !pauseOnBattery {
            let drift = CABasicAnimation(keyPath: "transform.rotation.z")
            drift.fromValue = -0.3; drift.toValue = 0.5; drift.duration = 24
            drift.autoreverses = true; drift.repeatCount = .infinity
            drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            gradient.add(drift, forKey: "drift")
        }
    }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        videoLayer?.frame = bounds
        motionLayer?.frame = bounds.insetBy(dx: -bounds.width / 2, dy: -bounds.height / 2)
        CATransaction.commit()
    }
    private func clear() {
        player?.pause(); looper?.disableLooping()
        videoLayer?.removeFromSuperlayer(); motionLayer?.removeFromSuperlayer()
        player = nil; looper = nil; videoLayer = nil; motionLayer = nil
    }
    override func stopAnimation() { clear(); super.stopAnimation() }
}
