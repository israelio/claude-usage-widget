#!/usr/bin/env swift
// Renders the app icon (gauge + star) and writes App/Assets.xcassets/AppIcon.appiconset.
// Usage: swift scripts/make-icon.swift
import AppKit

let S: CGFloat = 1024

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func lerp(_ a: NSColor, _ b: NSColor, _ t: CGFloat) -> NSColor {
    let x = a.usingColorSpace(.sRGB)!, y = b.usingColorSpace(.sRGB)!
    return NSColor(srgbRed: x.redComponent + (y.redComponent - x.redComponent) * t,
                   green: x.greenComponent + (y.greenComponent - x.greenComponent) * t,
                   blue: x.blueComponent + (y.blueComponent - x.blueComponent) * t, alpha: 1)
}

func render() -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // Tile (Apple icon grid: 824pt body inside 1024 canvas)
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let path = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

    // Drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: NSColor.black.withAlphaComponent(0.45).cgColor)
    color(0x14172B).setFill(); path.fill()
    ctx.restoreGState()

    // Background gradient
    ctx.saveGState(); path.addClip()
    NSGradient(colors: [color(0x2E3260), color(0x151832), color(0x0B0D1C)], atLocations: [0, 0.55, 1],
               colorSpace: .sRGB)!.draw(in: tile, angle: -90)
    // soft glow behind gauge
    NSGradient(colors: [color(0x6C7CFF, 0.30), color(0x6C7CFF, 0)], atLocations: [0, 1], colorSpace: .sRGB)!
        .draw(fromCenter: NSPoint(x: 512, y: 540), radius: 0, toCenter: NSPoint(x: 512, y: 540), radius: 380, options: [])
    ctx.restoreGState()

    // Gauge: 270° sweep, gap at the bottom
    let c = NSPoint(x: 512, y: 520)
    let r: CGFloat = 270, w: CGFloat = 78
    let startDeg: CGFloat = 225, sweep: CGFloat = 270       // clockwise from lower-left, through top, to lower-right
    let progress: CGFloat = 0.72

    func arc(from a: CGFloat, to b: CGFloat) -> NSBezierPath {
        let p = NSBezierPath()
        p.appendArc(withCenter: c, radius: r, startAngle: a, endAngle: b, clockwise: true)
        p.lineWidth = w; p.lineCapStyle = .round
        return p
    }
    // track
    color(0xFFFFFF, 0.10).setStroke()
    arc(from: startDeg, to: startDeg - sweep).stroke()

    // progress, drawn as short segments so the colour can shift green -> amber -> orange
    let steps = 90
    let total = sweep * progress
    for i in 0..<steps {
        let t0 = CGFloat(i) / CGFloat(steps), t1 = CGFloat(i + 1) / CGFloat(steps)
        let a0 = startDeg - total * t0, a1 = startDeg - total * min(1, t1 + 0.012)
        let t = (t0 + t1) / 2
        let col = t < 0.55 ? lerp(color(0x22D3A0), color(0xFBD24A), t / 0.55)
                           : lerp(color(0xFBD24A), color(0xFF7A3D), (t - 0.55) / 0.45)
        col.setStroke()
        let seg = NSBezierPath()
        seg.appendArc(withCenter: c, radius: r, startAngle: a0, endAngle: a1, clockwise: true)
        seg.lineWidth = w; seg.lineCapStyle = (i == 0 || i == steps - 1) ? .round : .butt
        seg.stroke()
    }
    // glow on the leading end
    let endA = (startDeg - total) * .pi / 180
    let tip = NSPoint(x: c.x + r * cos(endA), y: c.y + r * sin(endA))
    NSGradient(colors: [color(0xFF9A5A, 0.55), color(0xFF9A5A, 0)], atLocations: [0, 1], colorSpace: .sRGB)!
        .draw(fromCenter: tip, radius: 0, toCenter: tip, radius: 90, options: [])

    // Star in the middle (Staraware)
    func star(center: NSPoint, outer: CGFloat, inner: CGFloat) -> NSBezierPath {
        let p = NSBezierPath()
        for i in 0..<10 {
            let ang = (CGFloat(i) * 36 + 90) * .pi / 180
            let rad = i % 2 == 0 ? outer : inner
            let pt = NSPoint(x: center.x + rad * cos(ang), y: center.y + rad * sin(ang))
            i == 0 ? p.move(to: pt) : p.line(to: pt)
        }
        p.close(); p.lineJoinStyle = .round; return p
    }
    let sp = star(center: NSPoint(x: 512, y: 505), outer: 150, inner: 66)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 40, color: color(0xFFC83D, 0.7).cgColor)
    color(0xFFC83D).setFill(); sp.fill()
    ctx.restoreGState()
    ctx.saveGState(); sp.addClip()
    NSGradient(colors: [color(0xFFE88A), color(0xFFB62E)], atLocations: [0, 1], colorSpace: .sRGB)!
        .draw(in: sp.bounds, angle: -90)
    ctx.restoreGState()

    // Glass highlight on top of tile
    ctx.saveGState(); path.addClip()
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.20), NSColor.white.withAlphaComponent(0)],
               atLocations: [0, 1], colorSpace: .sRGB)!
        .draw(in: NSRect(x: 100, y: 560, width: 824, height: 364), angle: -90)
    ctx.restoreGState()
    // hairline edge
    NSColor.white.withAlphaComponent(0.18).setStroke()
    let edge = NSBezierPath(roundedRect: tile.insetBy(dx: 1.5, dy: 1.5), xRadius: 184, yRadius: 184)
    edge.lineWidth = 3; edge.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func png(_ rep: NSBitmapImageRep, size: Int) -> Data {
    let img = NSImage(size: NSSize(width: S, height: S)); img.addRepresentation(rep)
    let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
    NSGraphicsContext.current?.imageInterpolation = .high
    img.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return out.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let set = root.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
try Data(#"{"info":{"version":1,"author":"xcode"}}"#.utf8)
    .write(to: root.appendingPathComponent("App/Assets.xcassets/Contents.json"))

let rep = render()
let specs: [(pt: Int, scale: Int)] = [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)]
var images: [String] = []
for s in specs {
    let name = "icon_\(s.pt)x\(s.pt)\(s.scale == 2 ? "@2x" : "").png"
    try png(rep, size: s.pt * s.scale).write(to: set.appendingPathComponent(name))
    images.append(#"{"idiom":"mac","size":"\#(s.pt)x\#(s.pt)","scale":"\#(s.scale)x","filename":"\#(name)"}"#)
}
try Data(#"{"images":[\#(images.joined(separator: ","))],"info":{"version":1,"author":"xcode"}}"#.utf8)
    .write(to: set.appendingPathComponent("Contents.json"))
try png(rep, size: 1024).write(to: root.appendingPathComponent("docs/images/icon.png"))
print("wrote icon set + docs/images/icon.png")
