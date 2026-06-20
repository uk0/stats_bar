import AppKit

// Renders the macstatus app icon as a full .iconset (each size drawn from
// vector primitives so small sizes stay crisp), plus a logo.png for the README.
// Run from the repo root:  swift scripts/make_icon.swift

let outIconset = "build/macstatus.iconset"
let outLogo = "assets/logo.png"

func draw(size S: CGFloat) -> NSBitmapImageRep {
    let px = Int(S)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("cannot create bitmap rep") }
    rep.size = NSSize(width: S, height: S)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    NSColor.clear.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: S, height: S)).fill()

    // Graphite squircle background with a vertical gradient.
    let margin = S * 0.045
    let rect = NSRect(x: margin, y: margin, width: S - 2 * margin, height: S - 2 * margin)
    let radius = rect.width * 0.2237
    let bg = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    if let grad = NSGradient(
        starting: NSColor(srgbRed: 0.22, green: 0.22, blue: 0.245, alpha: 1),
        ending: NSColor(srgbRed: 0.10, green: 0.10, blue: 0.115, alpha: 1)
    ) { grad.draw(in: bg, angle: -90) }
    NSColor(white: 1, alpha: 0.07).setStroke()
    bg.lineWidth = S * 0.005
    bg.stroke()

    // Three status bars: green / orange / red, increasing height.
    let plotW = rect.width * 0.60
    let plotX = rect.midX - plotW / 2
    let gap = plotW * 0.13
    let barW = (plotW - 2 * gap) / 3
    let baseY = rect.minY + rect.height * 0.205
    let maxH = rect.height * 0.56
    let heights: [CGFloat] = [0.46, 0.72, 0.98]
    let colors = [
        NSColor(srgbRed: 0.204, green: 0.780, blue: 0.349, alpha: 1), // #34C759
        NSColor(srgbRed: 1.000, green: 0.624, blue: 0.039, alpha: 1), // #FF9F0A
        NSColor(srgbRed: 1.000, green: 0.231, blue: 0.188, alpha: 1), // #FF3B30
    ]

    // Baseline under the bars.
    NSColor(white: 1, alpha: 0.08).setFill()
    let blH = S * 0.012
    NSBezierPath(
        roundedRect: NSRect(x: plotX, y: baseY - blH * 0.4, width: plotW, height: blH),
        xRadius: blH / 2, yRadius: blH / 2
    ).fill()

    for i in 0 ..< 3 {
        let h = maxH * heights[i]
        let x = plotX + CGFloat(i) * (barW + gap)
        let cr = barW / 2
        let path = NSBezierPath(
            roundedRect: NSRect(x: x, y: baseY, width: barW, height: h),
            xRadius: cr, yRadius: cr
        )
        colors[i].setFill()
        path.fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, _ path: String) {
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("png encode") }
    try! data.write(to: URL(fileURLWithPath: path))
}

let fm = FileManager.default
try? fm.createDirectory(atPath: outIconset, withIntermediateDirectories: true)
try? fm.createDirectory(atPath: "assets", withIntermediateDirectories: true)

let entries: [(String, CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, size) in entries {
    writePNG(draw(size: size), "\(outIconset)/\(name).png")
}
writePNG(draw(size: 512), outLogo)
print("icon assets written")
