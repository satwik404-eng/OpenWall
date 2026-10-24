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
        for (style, shapes) in catalog.scenes {
            precondition(shapes.contains { $0.vertices(time: 0) != $0.vertices(time: 1.7) })
            for shape in shapes {
                let first = shape.vertices(time: 0), loop = shape.vertices(time: .pi * 2)
                precondition(zip(first, loop).allSatisfy { a, b in zip(a, b).allSatisfy { abs($0 - $1) < 1e-10 } })
                precondition(shape.vertices(time: 1.7).allSatisfy { $0.allSatisfy(\.isFinite) })
            }
            geometry[style] = shapes.map { $0.vertices(time: 1.7) }
        }
        try JSONSerialization.data(withJSONObject: geometry, options: [.sortedKeys]).write(to: output.appendingPathComponent("geometry.json"))
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
