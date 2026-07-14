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

    /// One loop of face transforms. A single still frame for the calm moods.
    func faceFrames() -> [FaceFrame] {
        func ring(_ n: Int, _ body: (Double) -> FaceFrame) -> [FaceFrame] {
            (0 ..< n).map { body(Double($0) / Double(n) * 2 * Double.pi) }
        }
        switch self {
        case .resting, .idle, .working:
            return [.still]
        case .busy:
            return ring(8) { t in
                FaceFrame(scale: CGFloat(1 + sin(t) * 0.06), dy: CGFloat(abs(sin(t)) * 0.6))
            }
        case .onFire:
            return ring(8) { t in
                let flick = sin(t * 2) * 0.09 + sin(t * 3) * 0.05
                return FaceFrame(scale: CGFloat(1.05 + flick),
                                 dx: CGFloat(sin(t * 4) * 0.4),
                                 dy: CGFloat(sin(t * 2) * 0.5 + 0.5),
                                 alpha: CGFloat(0.9 + 0.1 * (0.5 + 0.5 * sin(t * 3))))
            }
        }
    }
}

/// A single animation frame's transform for the state emoji.
struct FaceFrame {
    var scale: CGFloat = 1
    var dx: CGFloat = 0
    var dy: CGFloat = 0
    var alpha: CGFloat = 1
    static let still = FaceFrame()
}
