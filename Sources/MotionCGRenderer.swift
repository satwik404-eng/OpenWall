import AppKit

/// Native screen-saver drawing avoids embedding a SwiftUI application in the OS host.
enum MotionCGRenderer {
    static func draw(_ id: String, time: Double, size: CGSize, in context: CGContext) {
        let catalog = MotionCatalog.shared, item = MotionCatalog.item(id)
        let rect = CGRect(origin: .zero, size: size)
        func paint(_ fill: MotionFill) {
            let colors = fill.stops.map { stop -> CGColor in
                let c = stop.color < 0 ? [1.0,1.0,1.0] : item.palette[stop.color]
                return CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [CGFloat(c[0]), CGFloat(c[1]), CGFloat(c[2]), CGFloat(stop.alpha)])!
            }
            if fill.kind == "solid" { context.setFillColor(colors[0]); context.fill(rect); return }
            let locations: [CGFloat] = fill.stops.map { CGFloat($0.location) }
            let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
            let start = CGPoint(x: fill.start[0] * size.width, y: fill.start[1] * size.height)
            let options: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            if fill.kind == "radial" {
                context.drawRadialGradient(gradient, startCenter: start, startRadius: 0, endCenter: start, endRadius: fill.end[1] * min(size.width, size.height), options: options)
            } else {
                context.drawLinearGradient(gradient, start: start, end: CGPoint(x: fill.end[0] * size.width, y: fill.end[1] * size.height), options: options)
            }
        }
        context.setFillColor(NSColor.black.cgColor); context.fill(rect)
        paint(catalog.background)
        for shape in catalog.scenes[item.style] ?? [] {
            let vertices = shape.vertices(time: time)
            guard let first = vertices.first else { continue }
            context.saveGState(); context.setAlpha(shape.opacity(time: time)); context.beginPath()
            if shape.pixelRadius > 0 {
                context.addEllipse(in: CGRect(x: first[0] * size.width, y: first[1] * size.height, width: shape.pixelRadius * 2, height: shape.pixelRadius * 2))
            } else {
                context.move(to: CGPoint(x: first[0] * size.width, y: first[1] * size.height))
                for p in vertices.dropFirst() { context.addLine(to: CGPoint(x: p[0] * size.width, y: p[1] * size.height)) }
                if shape.closed { context.closePath() }
            }
            if shape.stroke > 0 { context.setLineWidth(shape.stroke * min(size.width, size.height)); context.replacePathWithStrokedPath() }
            context.clip(); paint(shape.fill); context.restoreGState()
        }
    }
}
