// Draws the Tato app icon (a white T with a Claude-orange touch dot on warm graphite) into a 1024x1024 PNG.
// Colours match Sources/touchbar-temp/Palette.swift.
// Usage: swiftc -O Tools/make-icon.swift -o /tmp/make-icon -framework AppKit && /tmp/make-icon Resources/AppIcon.png
import AppKit

func hex(_ h: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((h >> 16) & 255) / 255, green: CGFloat((h >> 8) & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: 1)
}

/// Apple-style superellipse ("squircle").
func squircle(_ r: NSRect, n: CGFloat = 5.6) -> NSBezierPath {
    let p = NSBezierPath(), a = r.width / 2
    for i in 0...360 {
        let t = CGFloat(i) / 360 * 2 * .pi, c = cos(t), s = sin(t)
        let pt = NSPoint(x: r.midX + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n), y: r.midY + a * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n))
        i == 0 ? p.move(to: pt) : p.line(to: pt)
    }
    p.close(); return p
}

func pill(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
    let r = min(w, h) / 2
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r).fill()
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = squircle(body)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowBlurRadius = 26; shadow.shadowOffset = NSSize(width: 0, height: -12); shadow.shadowColor = NSColor(white: 0, alpha: 0.35)
shadow.set(); NSColor.black.setFill(); shape.fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
shape.setClip()
hex(0x1F1E1D).setFill(); body.fill()                  // Palette.ink
hex(0xF0EEE6).setFill()                               // Palette.cream
pill(262, 626, 500, 128)      // top bar of the T
pill(448, 250, 128, 440)      // stem
hex(0xD97757).setFill()                               // Palette.clay
NSBezierPath(ovalIn: NSRect(x: 638, y: 326, width: 124, height: 124)).fill()   // the touch point
NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.restoreGraphicsState()

try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
