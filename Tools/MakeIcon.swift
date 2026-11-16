import AppKit

// Original vector artwork for the local notch, file and music utility.
func color(_ rgb: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
            green: CGFloat((rgb >> 8) & 255) / 255,
            blue: CGFloat(rgb & 255) / 255, alpha: alpha)
}
func round(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r)
}
func fill(_ path: NSBezierPath, _ rgb: UInt32, alpha: CGFloat = 1) {
    color(rgb, alpha: alpha).setFill()
    path.fill()
}
func line(_ path: NSBezierPath, _ rgb: UInt32, _ width: CGFloat, alpha: CGFloat = 1) {
    color(rgb, alpha: alpha).setStroke()
    path.lineWidth = width
    path.stroke()
}
func drawIcon() {
    let tile = round(76, 76, 872, 872, 188)
    NSGradient(starting: color(0x254955), ending: color(0x0B1420))!.draw(in: tile, angle: -64)
    line(round(79, 79, 866, 866, 185), 0xB8EFE4, 5, alpha: 0.28)

    let display = round(165, 292, 694, 432, 72)
    NSGradient(starting: color(0x274450), ending: color(0x132632))!.draw(in: display, angle: -90)
    line(display, 0x89BDBE, 10, alpha: 0.62)
    let notch = NSBezierPath()
    notch.move(to: NSPoint(x: 384, y: 726))
    notch.line(to: NSPoint(x: 640, y: 726))
    notch.line(to: NSPoint(x: 640, y: 666))
    notch.curve(to: NSPoint(x: 612, y: 638), controlPoint1: NSPoint(x: 640, y: 649), controlPoint2: NSPoint(x: 629, y: 638))
    notch.line(to: NSPoint(x: 412, y: 638))
    notch.curve(to: NSPoint(x: 384, y: 666), controlPoint1: NSPoint(x: 395, y: 638), controlPoint2: NSPoint(x: 384, y: 649))
    notch.close()
    fill(notch, 0x09131E)
    fill(round(501, 675, 22, 22, 11), 0x81E9C6)

    // Folder tab and body.
    fill(round(258, 402, 107, 146, 19), 0x89C5F5)
    let folder = round(258, 395, 199, 121, 23)
    NSGradient(starting: color(0x98DBFF), ending: color(0x6CB7EF))!.draw(in: folder, angle: -90)
    fill(round(282, 483, 151, 5, 2.5), 0xEAF9FF, alpha: 0.52)

    // Music note.
    let note = NSBezierPath()
    note.move(to: NSPoint(x: 625, y: 539))
    note.line(to: NSPoint(x: 744, y: 565))
    note.line(to: NSPoint(x: 744, y: 441))
    note.line(to: NSPoint(x: 719, y: 438))
    note.line(to: NSPoint(x: 719, y: 527))
    note.line(to: NSPoint(x: 650, y: 512))
    note.line(to: NSPoint(x: 650, y: 418))
    note.line(to: NSPoint(x: 625, y: 413))
    note.close()
    fill(note, 0xA0F4D5)
    fill(NSBezierPath(ovalIn: NSRect(x: 571, y: 389, width: 79, height: 55)), 0xA0F4D5)
    fill(NSBezierPath(ovalIn: NSRect(x: 665, y: 412, width: 79, height: 55)), 0xA0F4D5)
    fill(round(208, 231, 608, 24, 12), 0xA7D6D8, alpha: 0.66)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for (name, size) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
                     ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
                     ("512x512", 512), ("512x512@2x", 1024)] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                  samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                  bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let context = NSGraphicsContext.current!.cgContext
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("icon_\(name).png"))
}
