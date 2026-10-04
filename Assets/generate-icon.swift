import AppKit

guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: swift generate-icon.swift <iconset directory>")
}

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

for (name, size) in sizes {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                        isPlanar: false, colorSpaceName: .deviceRGB,
                                        bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Cannot create icon bitmap")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let scale = CGFloat(size)
    let square = NSBezierPath(roundedRect: NSRect(x: scale * 0.04, y: scale * 0.04,
                                                  width: scale * 0.92, height: scale * 0.92),
                              xRadius: scale * 0.21, yRadius: scale * 0.21)
    let gradient = NSGradient(starting: NSColor(calibratedRed: 0.49, green: 0.88, blue: 0.85, alpha: 1),
                              ending: NSColor(calibratedRed: 0.01, green: 0.52, blue: 0.58, alpha: 1))!
    gradient.draw(in: square, angle: -55)

    guard let symbol = NSImage(systemSymbolName: "text.cursor", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: scale * 0.51, weight: .medium)) else {
        fatalError("The text.cursor SF Symbol is unavailable")
    }
    let symbolSize = symbol.size
    let symbolRect = NSRect(x: (scale - symbolSize.width) / 2,
                            y: (scale - symbolSize.height) / 2,
                            width: symbolSize.width, height: symbolSize.height)
    context.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
    symbol.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1)
    context.cgContext.setBlendMode(.sourceIn)
    NSColor.white.setFill()
    context.cgContext.fill(symbolRect)
    context.cgContext.endTransparencyLayer()

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Cannot encode icon bitmap")
    }
    try data.write(to: directory.appendingPathComponent(name))
}
