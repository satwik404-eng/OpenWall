import Foundation

private final class MotionBundleToken: NSObject {}

struct MotionFill: Decodable {
    struct Stop: Decodable { let color: Int; let alpha, location: Double }
    let kind: String
    let stops: [Stop]
    let start, end: [Double]
}
struct MotionShape: Decodable {
    let points: [[Double]]
    let closed: Bool
    let stroke: Double
    let pivot: [Double]
    let rotation, rotate, driftX, driftY, pulse, rate, phase, warpX, warpY, frequency, pixelRadius, opacityPulse, opacityRate, opacityPhase: Double
    let fill: MotionFill
    func opacity(time: Double) -> Double { 1 - opacityPulse * (0.5 + 0.5 * sin(time * opacityRate + opacityPhase)) }
    func vertices(time: Double) -> [[Double]] {
        let t = time * rate + phase
        let angle = rotation + sin(t) * rotate
        let scale = 1 + sin(t) * pulse
        let dx = sin(t) * driftX, dy = cos(t) * driftY
        let co = cos(angle), si = sin(angle)
        return points.map { p in
            let warp = p.count > 2 ? p[2] : 0
            let x = p[0] + cos(p[1] * frequency + t) * warpX * warp
            let y = p[1] + sin(p[0] * frequency + t) * warpY * warp
            let a = (x - pivot[0]) * scale, b = (y - pivot[1]) * scale
            return [pivot[0] + a * co - b * si + dx, pivot[1] + a * si + b * co + dy]
        }
    }
}
struct MotionItem: Decodable { let id, name, style: String; let palette: [[Double]] }
struct MotionCatalog: Decodable {
    let version: Int
    let items: [MotionItem]
    let scenes: [String: [MotionShape]]
    let background: MotionFill
    static let shared: MotionCatalog = {
        let bundles = [Bundle(for: MotionBundleToken.self), Bundle.main]
        let urls = bundles.compactMap { $0.url(forResource: "motion-catalog", withExtension: "json") }
            + [URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Shared/motion-catalog.json")]
        for url in urls {
            if let data = try? Data(contentsOf: url), let catalog = try? JSONDecoder().decode(MotionCatalog.self, from: data), !catalog.items.isEmpty {
                return catalog
            }
        }
        preconditionFailure("OpenWall's bundled motion catalog is missing. Reinstall the complete app.")
    }()
    static let byID = Dictionary(uniqueKeysWithValues: shared.items.map { ($0.id, $0) })
    static func item(_ id: String) -> MotionItem { byID[id] ?? shared.items[0] }
}
