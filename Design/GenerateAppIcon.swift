import AppKit

// Original vector artwork. Coordinates use a 1024-point, bottom-left-origin canvas.
func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
}
func rounded(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}
func shadow(_ blur: CGFloat, _ offset: NSSize, _ opacity: CGFloat) {
    let s = NSShadow()
    s.shadowColor = NSColor.black.withAlphaComponent(opacity)
    s.shadowBlurRadius = blur
    s.shadowOffset = offset
    s.set()
}
func arrow(from start: NSPoint, to end: NSPoint, thickness: CGFloat) {
    let path = NSBezierPath()
    path.lineWidth = thickness
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.move(to: start)
    path.line(to: end)
    let direction: CGFloat = end.x > start.x ? 1 : -1
    path.move(to: NSPoint(x: end.x - direction * 67, y: end.y + 66))
    path.line(to: end)
    path.line(to: NSPoint(x: end.x - direction * 67, y: end.y - 66))
    color(0x087C70).setStroke()
    path.stroke()
}
func drawIcon() {
    let tile = rounded(NSRect(x: 100, y: 100, width: 824, height: 824), 184)
    NSGraphicsContext.saveGraphicsState()
    shadow(25, NSSize(width: 0, height: -13), 0.20)
    color(0x148F7F).setFill(); tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [color(0x077B70), color(0x24BD92), color(0x63DBAA)])!.draw(in: tile, angle: 75)
    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    let rim = rounded(NSRect(x: 103, y: 103, width: 818, height: 818), 181)
    NSColor.white.withAlphaComponent(0.27).setStroke(); rim.lineWidth = 4; rim.stroke()
    NSGraphicsContext.restoreGraphicsState()

    // Folder tab and back plate.
    let back = NSBezierPath()
    back.move(to: NSPoint(x: 245, y: 350))
    back.line(to: NSPoint(x: 245, y: 682))
    back.curve(to: NSPoint(x: 285, y: 722), controlPoint1: NSPoint(x: 245, y: 705), controlPoint2: NSPoint(x: 262, y: 722))
    back.line(to: NSPoint(x: 421, y: 722))
    back.curve(to: NSPoint(x: 452, y: 708), controlPoint1: NSPoint(x: 435, y: 722), controlPoint2: NSPoint(x: 443, y: 718))
    back.line(to: NSPoint(x: 486, y: 671))
    back.line(to: NSPoint(x: 739, y: 671))
    back.curve(to: NSPoint(x: 779, y: 631), controlPoint1: NSPoint(x: 762, y: 671), controlPoint2: NSPoint(x: 779, y: 654))
    back.line(to: NSPoint(x: 779, y: 350)); back.close()
    NSGraphicsContext.saveGraphicsState()
    shadow(18, NSSize(width: 0, height: -12), 0.12)
    color(0xC8F1DE).setFill(); back.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [color(0xC2EBD9), color(0xE8FFF0)])!.draw(in: back, angle: 90)

    // The clean front panel carries the entire transfer mark.
    let front = rounded(NSRect(x: 225, y: 288, width: 574, height: 339), 49)
    NSGraphicsContext.saveGraphicsState()
    shadow(22, NSSize(width: 0, height: -15), 0.19)
    color(0xF2FFF8).setFill(); front.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [color(0xE5F6EE), color(0xFFFFFF)])!.draw(in: front, angle: 90)
    NSColor.white.withAlphaComponent(0.85).setStroke(); front.lineWidth = 3; front.stroke()
    arrow(from: NSPoint(x: 366, y: 524), to: NSPoint(x: 659, y: 524), thickness: 42)
    arrow(from: NSPoint(x: 658, y: 399), to: NSPoint(x: 365, y: 399), thickness: 42)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let catalog = root.appendingPathComponent("AndroidTransmit/Assets.xcassets/AppIcon.appiconset")
let slots: [(Int, Int)] = [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)]
var images: [[String: String]] = []
for (size, scale) in slots {
    let pixels = size * scale
    let representation = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: representation)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let transform = NSAffineTransform()
    transform.scale(by: CGFloat(pixels) / 1024)
    transform.concat()
    drawIcon()
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    let filename = "AppIcon-\(size)@\(scale)x.png"
    let data = representation.representation(using: .png, properties: [:])!
    try data.write(to: catalog.appendingPathComponent(filename))
    if pixels == 1024 { try data.write(to: root.appendingPathComponent("Design/AppIcon-1024.png")) }
    images.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": filename])
}
let json: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]).write(to: catalog.appendingPathComponent("Contents.json"))
print("Generated all 10 macOS AppIcon slots and Design/AppIcon-1024.png")
