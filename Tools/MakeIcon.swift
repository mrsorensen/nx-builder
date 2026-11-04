// Draws the app icon: a 1024×1024 PNG, written to the path given.
import AppKit

let size = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// The macOS icon grid: an 824-point rounded square in a 1024 canvas.
let box = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: box, xRadius: 185, yRadius: 185)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.shadowBlurRadius = 24
shadow.set()
NSColor.black.setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

NSGradient(colors: [NSColor(calibratedRed: 0.36, green: 0.30, blue: 0.95, alpha: 1),
                    NSColor(calibratedRed: 0.10, green: 0.62, blue: 0.85, alpha: 1)])!
    .draw(in: shape, angle: -60)

func symbol(_ name: String, points: CGFloat, in rect: NSRect, alpha: CGFloat) {
    let config = NSImage.SymbolConfiguration(pointSize: points, weight: .semibold)
        .applying(.init(paletteColors: [NSColor.white.withAlphaComponent(alpha)]))
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else { return }
    let s = image.size
    let scale = min(rect.width / s.width, rect.height / s.height)
    let w = s.width * scale, h = s.height * scale
    image.draw(in: NSRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h))
}

symbol("gamecontroller.fill", points: 400, in: NSRect(x: 190, y: 410, width: 644, height: 400), alpha: 1)
symbol("hammer.fill", points: 200, in: NSRect(x: 610, y: 160, width: 210, height: 210), alpha: 0.9)

NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: out))
