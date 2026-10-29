import AppKit

let size = 1024
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("无法创建画布\n", stderr)
    exit(1)
}
rep.size = NSSize(width: size, height: size)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let bounds = NSRect(x: 0, y: 0, width: size, height: size)
NSGradient(colors: [
    NSColor(srgbRed: 0.13, green: 0.27, blue: 0.82, alpha: 1),
    NSColor(srgbRed: 0.34, green: 0.60, blue: 1.00, alpha: 1),
])?.draw(in: bounds, angle: 90)

NSColor.white.setFill()
NSBezierPath(roundedRect: NSRect(x: 212, y: 300, width: 520, height: 430), xRadius: 78, yRadius: 78).fill()

NSColor(srgbRed: 1.00, green: 0.33, blue: 0.24, alpha: 1).setFill()
let shutter = NSRect(x: 548, y: 176, width: 312, height: 312)
NSBezierPath(ovalIn: shutter).fill()
NSColor.white.setFill()
NSBezierPath(ovalIn: shutter.insetBy(dx: 112, dy: 112)).fill()

NSGraphicsContext.restoreGraphicsState()

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "icon.png")
guard let png = rep.representation(using: .png, properties: [:]) else {
    fputs("无法编码 PNG\n", stderr)
    exit(1)
}
do {
    try png.write(to: out)
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}
