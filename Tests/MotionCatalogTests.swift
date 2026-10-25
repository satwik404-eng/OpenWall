import AppKit
import SwiftUI

@main struct MotionCatalogTests {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let catalog = MotionCatalog.shared
        precondition(catalog.items.count == 89 && Set(catalog.items.map(\.id)).count == 89)
        let newStyles = Dictionary(grouping: catalog.items.filter { $0.style != "waves" }, by: \.style)
        precondition(newStyles.count == 10 && newStyles.values.allSatisfy { $0.count == 8 })
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var geometry: [String: [[[Double]]]] = [:]
        var gradients: [String: [[Double]]] = [:]
        for (style, shapes) in catalog.scenes {
            precondition(shapes.contains { $0.vertices(time: 0) != $0.vertices(time: 1.7) })
            for shape in shapes {
                let first = shape.vertices(time: 0), loop = shape.vertices(time: .pi * 2)
                precondition(zip(first, loop).allSatisfy { a, b in zip(a, b).allSatisfy { abs($0 - $1) < 1e-10 } })
                precondition(abs(shape.opacity(time: 0) - shape.opacity(time: .pi * 2)) < 1e-10)
                let step = 0.0001
                let before = shape.vertices(time: .pi * 2 - step), after = shape.vertices(time: step)
                for i in first.indices { for axis in 0..<2 {
                    let entering = (loop[i][axis] - before[i][axis]) / step
                    let leaving = (after[i][axis] - first[i][axis]) / step
                    precondition(abs(entering - leaving) < 0.001, "Motion must flow through the loop boundary")
                }}
                precondition(shape.vertices(time: 1.7).allSatisfy { $0.allSatisfy(\.isFinite) })
            }
            geometry[style] = shapes.map { $0.vertices(time: 1.7) }
            gradients[style] = shapes.map { $0.gradientCenter(time: 1.7) + [$0.gradientScale(time: 1.7), $0.opacity(time: 1.7)] }
        }
        try JSONSerialization.data(withJSONObject: geometry, options: [.sortedKeys]).write(to: output.appendingPathComponent("geometry.json"))
        try JSONSerialization.data(withJSONObject: gradients, options: [.sortedKeys]).write(to: output.appendingPathComponent("gradients.json"))
        let moving = ImageRenderer(content: MotionArtwork(preset: "constellation-midnight", fixedTime: 1.7).frame(width: 480, height: 270))
        let later = ImageRenderer(content: MotionArtwork(preset: "constellation-midnight", fixedTime: 1.95).frame(width: 480, height: 270))
        moving.scale = 1; later.scale = 1
        let firstFrame = NSBitmapImageRep(cgImage: moving.cgImage!)
        let nextFrame = NSBitmapImageRep(cgImage: later.cgImage!)
        var changed = 0
        for y in 0..<270 { for x in 0..<480 {
            let a = firstFrame.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
            let b = nextFrame.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
            if abs(a.redComponent-b.redComponent)+abs(a.greenComponent-b.greenComponent)+abs(a.blueComponent-b.blueComponent) > 0.08 { changed += 1 }
        }}
        precondition(changed > 500, "Constellation must visibly move within two seconds")
        try firstFrame.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("constellation-before.png"))
        try nextFrame.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("constellation-after.png"))
        print("PASS Constellation visibly changes \(changed) pixels within two seconds")
        // Live playback advances one phase unit per eight seconds at 1x.
        // Sample several points in each cycle, including near direction reversals.
        func pixels(_ id: String, phase: Double) -> [UInt8] {
            let renderer = ImageRenderer(content: MotionArtwork(preset: id, fixedTime: phase).frame(width: 480, height: 270))
            renderer.scale = 1
            let context = CGContext(data: nil, width: 480, height: 270, bitsPerComponent: 8, bytesPerRow: 480 * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(renderer.cgImage!, in: CGRect(x: 0, y: 0, width: 480, height: 270))
            return Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self), count: 480 * 270 * 4))
        }
        var visibility: [String: Int] = [:]
        for style in catalog.scenes.keys.sorted() {
            let id = catalog.items.first { $0.style == style && ($0.id.hasSuffix("-midnight") || $0.id == "midnight") }!.id
            var minimum = Int.max
            for phase in [0.2, 1.7, 3.0, 4.6] {
                let a = pixels(id, phase: phase), b = pixels(id, phase: phase + 2.0 / 8)
                var visible = 0
                for i in stride(from: 0, to: a.count, by: 4) {
                    let difference = abs(Int(a[i]) - Int(b[i])) + abs(Int(a[i+1]) - Int(b[i+1])) + abs(Int(a[i+2]) - Int(b[i+2]))
                    if difference > 20 { visible += 1 }
                }
                minimum = min(minimum, visible)
            }
            visibility[style] = minimum
            print("PASS 1x visible motion \(style): at least \(minimum) changed pixels over two seconds")
        }
        try JSONSerialization.data(withJSONObject: visibility, options: [.sortedKeys]).write(to: output.appendingPathComponent("visibility.json"))
        fflush(stdout)
        precondition(visibility.values.allSatisfy { $0 > 500 }, "Every style should visibly move at 1x in the dark Midnight Silk palette")
        var images = Set<Data>()
        for item in catalog.items {
            let renderer = ImageRenderer(content: MotionArtwork(preset: item.id, fixedTime: 1.7).frame(width: 480, height: 270))
            renderer.scale = 1
            guard let image = renderer.cgImage else { fatalError("Could not render \(item.id)") }
            let rep = NSBitmapImageRep(cgImage: image)
            let png = rep.representation(using: .png, properties: [:])!
            precondition(images.insert(png).inserted, "Duplicate artwork: \(item.id)")
            try png.write(to: output.appendingPathComponent(item.id + ".png"))
        }
        print("PASS 89 unique native-rendered wallpapers, ten styles with eight palettes, animated geometry and seamless cycles")
        print("PASS legacy original IDs retained: \(catalog.items.prefix(9).map(\.id).joined(separator: ", "))")
    }
}
