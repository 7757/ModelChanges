import AppKit

// Renders the ModelChanges app icon: a compact routing mark that hints at
// switching between local models and connecting apps to them.
// Output: a single 1024×1024 PNG.

let size: CGFloat = 1024
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let rect = NSRect(x: 0, y: 0, width: size, height: size)
let cg = NSGraphicsContext.current!.cgContext

// Squircle clip
let squircle = NSBezierPath(roundedRect: rect, xRadius: size * 0.2237, yRadius: size * 0.2237)
squircle.addClip()

// Deep, less-common brand field: cool graphite into mineral teal.
let grad = NSGradient(colors: [
    NSColor(srgbRed: 0.075, green: 0.105, blue: 0.125, alpha: 1),
    NSColor(srgbRed: 0.045, green: 0.285, blue: 0.255, alpha: 1)
])!
grad.draw(in: rect, angle: -55)

// Quiet depth, not a generic glossy app-icon blob.
let cornerLight = NSGradient(colors: [
    NSColor(srgbRed: 0.68, green: 1.0, blue: 0.78, alpha: 0.20),
    NSColor(srgbRed: 0.68, green: 1.0, blue: 0.78, alpha: 0.0)
])!
cornerLight.draw(in: rect, relativeCenterPosition: NSPoint(x: -0.35, y: 0.45))

let lowerGlow = NSGradient(colors: [
    NSColor(srgbRed: 0.20, green: 0.55, blue: 1.0, alpha: 0.18),
    NSColor(srgbRed: 0.20, green: 0.55, blue: 1.0, alpha: 0.0)
])!
lowerGlow.draw(in: rect, relativeCenterPosition: NSPoint(x: 0.45, y: -0.55))

func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    CGPoint(x: size * x, y: size * y)
}

// Shadowed "change path" mark.
let mark = NSBezierPath()
mark.move(to: point(0.24, 0.42))
mark.curve(to: point(0.40, 0.57), controlPoint1: point(0.30, 0.43), controlPoint2: point(0.33, 0.56))
mark.curve(to: point(0.55, 0.42), controlPoint1: point(0.47, 0.58), controlPoint2: point(0.49, 0.42))
mark.curve(to: point(0.76, 0.60), controlPoint1: point(0.64, 0.42), controlPoint2: point(0.67, 0.59))

cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -size * 0.018),
             blur: size * 0.035,
             color: NSColor(white: 0, alpha: 0.34).cgColor)
mark.lineWidth = size * 0.074
mark.lineCapStyle = .round
mark.lineJoinStyle = .round
NSColor(white: 1, alpha: 0.94).setStroke()
mark.stroke()
cg.restoreGState()

let accent = NSBezierPath()
accent.move(to: point(0.25, 0.43))
accent.curve(to: point(0.40, 0.57), controlPoint1: point(0.30, 0.43), controlPoint2: point(0.33, 0.56))
accent.lineWidth = size * 0.028
accent.lineCapStyle = .round
NSColor(srgbRed: 0.55, green: 1.0, blue: 0.70, alpha: 0.90).setStroke()
accent.stroke()

// Two model nodes: one "source", one selected destination.
func node(center: CGPoint, radius: CGFloat, fill: NSColor, stroke: NSColor, strokeWidth: CGFloat) {
    let r = radius
    let oval = NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -size * 0.012),
                 blur: size * 0.02,
                 color: NSColor(white: 0, alpha: 0.26).cgColor)
    fill.setFill()
    oval.fill()
    cg.restoreGState()
    oval.lineWidth = strokeWidth
    stroke.setStroke()
    oval.stroke()
}

node(center: point(0.24, 0.42),
     radius: size * 0.056,
     fill: NSColor(srgbRed: 0.54, green: 1.0, blue: 0.70, alpha: 1),
     stroke: NSColor(white: 1, alpha: 0.86),
     strokeWidth: size * 0.012)
node(center: point(0.76, 0.60),
     radius: size * 0.071,
     fill: NSColor(white: 1, alpha: 0.98),
     stroke: NSColor(srgbRed: 0.54, green: 1.0, blue: 0.70, alpha: 0.95),
     strokeWidth: size * 0.014)

// Small local-endpoint dot, tying the mark to "runs here".
let local = NSBezierPath(roundedRect: NSRect(x: size * 0.39, y: size * 0.31,
                                             width: size * 0.22, height: size * 0.055),
                         xRadius: size * 0.027, yRadius: size * 0.027)
NSColor(white: 1, alpha: 0.18).setFill()
local.fill()
NSColor(white: 1, alpha: 0.34).setStroke()
local.lineWidth = size * 0.006
local.stroke()

NSGraphicsContext.restoreGraphicsState()

let outURL = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png")
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try? png.write(to: outURL)
print("wrote \(outURL.path)")
