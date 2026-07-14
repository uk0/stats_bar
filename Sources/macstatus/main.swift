import AppKit

// Diagnostic mode: `macstatus --once` samples twice and prints to stdout, no GUI.
if CommandLine.arguments.contains("--once") {
    let monitor = SystemMonitor()
    _ = monitor.sample()                 // prime CPU baseline
    Thread.sleep(forTimeInterval: 0.7)   // let some ticks accumulate
    let m = monitor.sample()
    let gb = 1024.0 * 1024.0 * 1024.0
    print(String(format: "CPU  used: %5.1f%%", m.cpuUsage))
    print(String(format: "MEM  used: %5.1f%%  (%.2f / %.2f GB)",
                 m.memoryUsage, Double(m.memUsedBytes) / gb, Double(m.memTotalBytes) / gb))
    print(String(format: "DISK free: %5.1f%%  (%.1f / %.1f GB)",
                 m.diskFree, Double(m.diskFreeBytes) / gb, Double(m.diskTotalBytes) / gb))
    print("TIME  Beijing: \(Clock.now())")
    exit(0)
}

// Diagnostic mode: `macstatus --faces` renders the five state faces with labels
// to assets/faces.png (also a README asset), no GUI.
if CommandLine.arguments.contains("--faces") {
    let states = MachineState.allCases
    let pad: CGFloat = 20, cellW: CGFloat = 160, gap: CGFloat = 16
    let W = pad * 2 + CGFloat(states.count) * cellW + CGFloat(states.count - 1) * gap
    let H: CGFloat = 220
    let img = NSImage(size: NSSize(width: W, height: H))
    img.lockFocus()
    NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: W, height: H), xRadius: 36, yRadius: 36)
        .setClip()
    NSColor(srgbRed: 0.13, green: 0.13, blue: 0.15, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: W, height: H).fill()
    for (i, st) in states.enumerated() {
        let cx = pad + CGFloat(i) * (cellW + gap) + cellW / 2
        let emoji = NSAttributedString(string: st.emoji, attributes: [.font: NSFont.systemFont(ofSize: 92)])
        let es = emoji.size()
        emoji.draw(at: NSPoint(x: cx - es.width / 2, y: H - 38 - es.height))
        let label = NSAttributedString(string: st.label, attributes: [
            .font: NSFont.systemFont(ofSize: 30, weight: .medium),
            .foregroundColor: NSColor.white,
        ])
        let ls = label.size()
        label.draw(at: NSPoint(x: cx - ls.width / 2, y: 26))
    }
    img.unlockFocus()
    try? FileManager.default.createDirectory(atPath: "assets", withIntermediateDirectories: true)
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "assets/faces.png"))
    print("faces -> assets/faces.png")
    exit(0)
}

// Diagnostic mode: `macstatus --bar` renders the compact status-bar graphic on
// light and dark strips (scaled up) to build/bar.png, no GUI.
if CommandLine.arguments.contains("--bar") {
    let history: [Double] = (0 ..< 28).map { i in
        let t = Double(i)
        return 45.0 + 40.0 * sin(t * 0.45) + Double(i % 5) * 2.0
    }
    let bar = BarRenderer.image(cpu: 92, mem: 81, disk: 28, state: .onFire,
                                frame: .still, history: history, time: "07-01 12:38")
    let scale: CGFloat = 5
    let margin: CGFloat = 12
    let bw = bar.size.width, bh = bar.size.height
    let W = bw * scale + margin * 2
    let stripH = bh * scale + margin * 2
    let out = NSImage(size: NSSize(width: W, height: stripH * 2))
    out.lockFocus()
    func strip(y: CGFloat, bg: NSColor, appearance: NSAppearance.Name) {
        bg.setFill()
        NSRect(x: 0, y: y, width: W, height: stripH).fill()
        NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
            bar.draw(in: NSRect(x: margin, y: y + margin, width: bw * scale, height: bh * scale))
        }
    }
    strip(y: stripH, bg: NSColor(white: 0.14, alpha: 1), appearance: .darkAqua)
    strip(y: 0, bg: NSColor(white: 0.97, alpha: 1), appearance: .aqua)
    out.unlockFocus()
    try? FileManager.default.createDirectory(atPath: "build", withIntermediateDirectories: true)
    let rep = NSBitmapImageRep(data: out.tiffRepresentation!)!
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "build/bar.png"))
    print("bar -> build/bar.png")
    exit(0)
}

// Menu-bar accessory app: no Dock icon, no main window.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
