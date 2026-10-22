// Draws the app icon: the widget itself, four rows on a dark rounded square.
// Kept as a script so the icon is reproducible and needs no design tool.
import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "build/icon-1024.png"
let pixels = 1024
let size = CGFloat(pixels)

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixels,
    pixelsHigh: pixels,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    FileHandle.standardError.write(Data("cannot allocate the icon bitmap\n".utf8))
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let canvas = NSRect(x: 0, y: 0, width: size, height: size)
NSColor.clear.setFill()
canvas.fill()

let body = NSBezierPath(roundedRect: canvas.insetBy(dx: 58, dy: 58), xRadius: 200, yRadius: 200)
let background = NSGradient(
    starting: NSColor(calibratedRed: 0.16, green: 0.18, blue: 0.23, alpha: 1),
    ending: NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.09, alpha: 1)
)
background?.draw(in: body, angle: -90)

let amber = NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.30, alpha: 1)
let green = NSColor(calibratedRed: 0.36, green: 0.82, blue: 0.55, alpha: 1)
let grey = NSColor(calibratedWhite: 1.0, alpha: 0.30)

let dots: [NSColor] = [amber, amber, green, grey]
let widths: [CGFloat] = [430, 360, 470, 390]
let usable = size - 2 * 120
let rowHeight: CGFloat = usable / 4

for (index, dotColour) in dots.enumerated() {
    let top = size - 120 - CGFloat(index) * rowHeight
    let dotY = top - rowHeight * 0.28
    let dotRect = NSRect(x: 150, y: dotY - 20, width: 40, height: 40)
    dotColour.setFill()
    NSBezierPath(ovalIn: dotRect).fill()

    NSColor(calibratedWhite: 1.0, alpha: index == 3 ? 0.55 : 0.92).setFill()
    let title = NSRect(x: 225, y: dotY - 12, width: widths[index], height: 30)
    NSBezierPath(roundedRect: title, xRadius: 15, yRadius: 15).fill()

    NSColor(calibratedWhite: 1.0, alpha: 0.16).setFill()
    let meta = NSRect(x: 225, y: dotY - 52, width: 250, height: 14)
    NSBezierPath(roundedRect: meta, xRadius: 7, yRadius: 7).fill()

    NSColor(calibratedWhite: 1.0, alpha: 0.10).setFill()
    let bar = NSRect(x: 225, y: dotY - 84, width: 540, height: 12)
    NSBezierPath(roundedRect: bar, xRadius: 6, yRadius: 6).fill()

    (index == 0 ? amber : green).withAlphaComponent(0.85).setFill()
    let used = NSRect(x: 225, y: dotY - 84, width: 540 * (index == 0 ? 0.86 : 0.34), height: 12)
    NSBezierPath(roundedRect: used, xRadius: 6, yRadius: 6).fill()
}

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("cannot encode the icon\n".utf8))
    exit(1)
}

let url = URL(fileURLWithPath: output)
try? FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
do {
    try png.write(to: url)
} catch {
    FileHandle.standardError.write(Data("cannot write \(output): \(error)\n".utf8))
    exit(1)
}
