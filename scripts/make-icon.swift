import AppKit
import Foundation
let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Bitmap unavailable") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let scale = CGFloat(size) / 1024
    let transform = AffineTransform(scale: scale)
    (transform as NSAffineTransform).concat()
    NSColor(calibratedRed: 0.12, green: 0.32, blue: 0.29, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 50, y: 50, width: 924, height: 924), xRadius: 212, yRadius: 212).fill()
    NSColor(calibratedRed: 0.87, green: 0.96, blue: 0.89, alpha: 1).setStroke()
    let ring = NSBezierPath(ovalIn: NSRect(x: 236, y: 236, width: 552, height: 552)); ring.lineWidth = 44; ring.stroke()
    let wave = NSBezierPath(); wave.lineWidth = 43; wave.lineCapStyle = .round; wave.lineJoinStyle = .round
    wave.move(to: NSPoint(x: 277, y: 510)); wave.line(to: NSPoint(x: 410, y: 510)); wave.line(to: NSPoint(x: 467, y: 648)); wave.line(to: NSPoint(x: 550, y: 370)); wave.line(to: NSPoint(x: 611, y: 510)); wave.line(to: NSPoint(x: 746, y: 510)); wave.stroke()
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Icon rendering failed") }
    let names: [String]
    switch size {
    case 16: names = ["icon_16x16.png"]
    case 32: names = ["icon_16x16@2x.png", "icon_32x32.png"]
    case 64: names = ["icon_32x32@2x.png"]
    case 128: names = ["icon_128x128.png"]
    case 256: names = ["icon_128x128@2x.png", "icon_256x256.png"]
    case 512: names = ["icon_256x256@2x.png", "icon_512x512.png"]
    default: names = ["icon_512x512@2x.png"]
    }
    for name in names { try png.write(to: output.appendingPathComponent(name)) }
}
