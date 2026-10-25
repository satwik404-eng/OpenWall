import SwiftUI

struct MotionArtwork: View {
    let preset: String
    var animated = false
    var fixedTime: Double? = nil

    static func colors(for preset: String) -> [Color] {
        MotionCatalog.item(preset).palette.map { Color(.sRGB, red: $0[0], green: $0[1], blue: $0[2], opacity: 1) }
    }
    private static func shading(_ fill: MotionFill, palette: [Color], size: CGSize, opacity: Double = 1, center: [Double]? = nil, radiusScale: Double = 1) -> GraphicsContext.Shading {
        let stops = fill.stops.map { Gradient.Stop(color: ($0.color < 0 ? Color.white : palette[$0.color]).opacity($0.alpha * opacity), location: $0.location) }
        let gradient = Gradient(stops: stops)
        let start = CGPoint(x: fill.start[0] * size.width, y: fill.start[1] * size.height)
        if fill.kind == "solid" { return .color(stops[0].color) }
        if fill.kind == "radial" {
            let origin = center ?? fill.start
            return .radialGradient(gradient, center: CGPoint(x: origin[0] * size.width, y: origin[1] * size.height), startRadius: 0, endRadius: fill.end[1] * min(size.width, size.height) * radiusScale)
        }
        return .linearGradient(gradient, startPoint: start, endPoint: CGPoint(x: fill.end[0] * size.width, y: fill.end[1] * size.height))
    }
    var body: some View {
        let item = MotionCatalog.item(preset)
        let shapes = MotionCatalog.shared.scenes[item.style] ?? []
        let palette = Self.colors(for: preset)
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !animated)) { timeline in
            Canvas { context, size in
                let time = fixedTime ?? (animated ? timeline.date.timeIntervalSinceReferenceDate / 8 : 1.7)
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
                context.fill(Path(CGRect(origin: .zero, size: size)), with: Self.shading(MotionCatalog.shared.background, palette: palette, size: size))
                for shape in shapes {
                    let vertices = shape.vertices(time: time)
                    guard let first = vertices.first else { continue }
                    var path = Path()
                    if shape.pixelRadius > 0 {
                        path = Path(ellipseIn: CGRect(x: first[0] * size.width, y: first[1] * size.height, width: shape.pixelRadius * 2, height: shape.pixelRadius * 2))
                    } else {
                        path.move(to: CGPoint(x: first[0] * size.width, y: first[1] * size.height))
                        for point in vertices.dropFirst() { path.addLine(to: CGPoint(x: point[0] * size.width, y: point[1] * size.height)) }
                        if shape.closed { path.closeSubpath() }
                    }
                    let shader = Self.shading(shape.fill, palette: palette, size: size, opacity: shape.opacity(time: time), center: shape.gradientCenter(time: time), radiusScale: shape.gradientScale(time: time))
                    if shape.stroke > 0 { context.stroke(path, with: shader, lineWidth: shape.stroke * min(size.width, size.height)) }
                    else { context.fill(path, with: shader) }
                }
            }
        }
        .clipped()
        .accessibilityLabel("\(item.name) animated wallpaper")
    }
}
