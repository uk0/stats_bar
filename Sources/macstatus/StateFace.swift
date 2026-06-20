import AppKit

/// Overall machine mood, derived from CPU (with a memory safety valve).
enum MachineState: CaseIterable {
    case resting   // 休息   — almost nothing running
    case idle      // 清闲   — light, calm
    case working   // 工作中 — steady work
    case busy      // 繁忙   — heavy
    case onFire    // 火力全开 — maxed out

    var emoji: String {
        switch self {
        case .resting: return "😴"
        case .idle:    return "😌"
        case .working: return "🙂"
        case .busy:    return "😤"
        case .onFire:  return "🔥"
        }
    }

    var label: String {
        switch self {
        case .resting: return "休息"
        case .idle:    return "清闲"
        case .working: return "工作中"
        case .busy:    return "繁忙"
        case .onFire:  return "火力全开"
        }
    }

    /// Frame interval for the looping animation. `nil` means a static face
    /// (no timer, no extra wake-ups). Low-load moods stay still to keep the app
    /// at ~0% CPU when idle; only the busy moods animate — and they only occur
    /// when the machine is already working, so the redraw cost is in context.
    var animInterval: TimeInterval? {
        switch self {
        case .resting: return nil    // 😴 static — quiet & power-friendly
        case .idle:    return nil    // 😌 static
        case .working: return nil    // 🙂 static
        case .busy:    return 0.22   // 😤 gentle huff (~4.5 fps)
        case .onFire:  return 0.13   // 🔥 lively flame flicker (~7.7 fps)
        }
    }

    static func current(cpu: Double, mem: Double) -> MachineState {
        if cpu >= 85 || mem >= 95 { return .onFire }
        if cpu >= 60 { return .busy }
        if cpu >= 25 { return .working }
        if cpu >= 8  { return .idle }
        return .resting
    }
}

/// Renders the state emoji into a fixed-size image so the menu-bar text never
/// shifts, and pre-bakes one loop of animation frames per state.
enum StateFace {
    static let canvas: CGFloat = 18

    static func render(_ emoji: String, scale: CGFloat = 1, dx: CGFloat = 0,
                       dy: CGFloat = 0, alpha: CGFloat = 1) -> NSImage {
        let img = NSImage(size: NSSize(width: canvas, height: canvas))
        img.lockFocus()
        let font = NSFont.systemFont(ofSize: canvas * 0.72 * scale)
        let str = NSAttributedString(string: emoji, attributes: [.font: font])
        let sz = str.size()
        NSGraphicsContext.current?.cgContext.setAlpha(alpha)
        str.draw(at: NSPoint(x: (canvas - sz.width) / 2 + dx, y: (canvas - sz.height) / 2 + dy))
        img.unlockFocus()
        img.isTemplate = false
        return img
    }

    /// One full animation loop. Single-frame for static states.
    static func frames(for state: MachineState) -> [NSImage] {
        let e = state.emoji
        func ring(_ n: Int, _ body: (Double) -> NSImage) -> [NSImage] {
            (0 ..< n).map { body(Double($0) / Double(n) * 2 * Double.pi) }
        }
        switch state {
        case .resting, .idle, .working:
            return [render(e)]   // static face, single frame
        case .busy:
            return ring(8) { t in render(e, scale: CGFloat(1 + sin(t) * 0.06), dy: CGFloat(abs(sin(t))) * 0.6) }
        case .onFire:
            return ring(8) { t in
                let flick = sin(t * 2) * 0.09 + sin(t * 3) * 0.05
                return render(e,
                              scale: CGFloat(1.05 + flick),
                              dx: CGFloat(sin(t * 4)) * 0.4,
                              dy: CGFloat(sin(t * 2)) * 0.5 + 0.5,
                              alpha: CGFloat(0.9 + 0.1 * (0.5 + 0.5 * sin(t * 3))))
            }
        }
    }
}
