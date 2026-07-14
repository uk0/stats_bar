import AppKit

/// Draws the whole compact status-bar graphic into one image: the state emoji,
/// three ring gauges (CPU / MEM / DISK), a CPU sparkline, and the Beijing time.
///
/// The image uses a `drawingHandler`, so it re-renders at the menu bar's own
/// backing scale (crisp on Retina) and appearance (dynamic colors resolve to the
/// light/dark menu bar automatically).
enum BarRenderer {
    static let height: CGFloat = 18

    private static let numFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
    private static let timeFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)

    private static let emojiBox: CGFloat = 17
    private static let ringD: CGFloat = 15
    private static let sparkW: CGFloat = 26
    private static let ringNumGap: CGFloat = 3
    private static let groupGap: CGFloat = 6
    private static let padL: CGFloat = 2
    private static let padR: CGFloat = 3

    static func image(cpu: Int, mem: Int, disk: Int, state: MachineState,
                      frame: FaceFrame, history: [Double], time: String) -> NSImage {
        let cpuW = width("\(cpu)", numFont)
        let memW = width("\(mem)", numFont)
        let diskW = width("\(disk)", numFont)
        let timeW = width(time, timeFont)

        var w = padL + emojiBox + groupGap
        w += ringD + ringNumGap + cpuW + groupGap
        w += ringD + ringNumGap + memW + groupGap
        w += ringD + ringNumGap + diskW + groupGap
        w += sparkW + groupGap
        w += timeW + padR

        let img = NSImage(size: NSSize(width: w, height: height), flipped: false) { _ in
            let cy = height / 2
            var x = padL

            drawEmoji(state.emoji, frame: frame, x: x, box: emojiBox, cy: cy)
            x += emojiBox + groupGap

            func gauge(_ value: Int, _ numWidth: CGFloat, _ color: NSColor) {
                drawRing(cx: x + ringD / 2, cy: cy, d: ringD, fraction: CGFloat(value) / 100, color: color)
                x += ringD + ringNumGap
                drawText("\(value)", font: numFont, color: .labelColor, x: x, cy: cy)
                x += numWidth + groupGap
            }
            gauge(cpu, cpuW, usedColor(cpu))
            gauge(mem, memW, usedColor(mem))
            gauge(disk, diskW, freeColor(disk))

            drawSparkline(history, x: x, cy: cy, w: sparkW, h: 11, color: usedColor(cpu))
            x += sparkW + groupGap

            drawText(time, font: timeFont, color: .secondaryLabelColor, x: x, cy: cy)
            return true
        }
        img.isTemplate = false
        return img
    }

    // MARK: - Gauge colors

    /// Used metrics (CPU / memory): green → orange → red as it climbs.
    static func usedColor(_ p: Int) -> NSColor {
        p >= 90 ? .systemRed : (p >= 75 ? .systemOrange : .systemGreen)
    }

    /// Free disk: green while there's room, red when it runs out.
    static func freeColor(_ p: Int) -> NSColor {
        p <= 10 ? .systemRed : (p <= 20 ? .systemOrange : .systemGreen)
    }

    // MARK: - Primitives

    private static func width(_ s: String, _ font: NSFont) -> CGFloat {
        (s as NSString).size(withAttributes: [.font: font]).width
    }

    private static func drawEmoji(_ emoji: String, frame: FaceFrame, x: CGFloat, box: CGFloat, cy: CGFloat) {
        let str = NSAttributedString(string: emoji, attributes: [.font: NSFont.systemFont(ofSize: 13 * frame.scale)])
        let sz = str.size()
        let ctx = NSGraphicsContext.current?.cgContext
        ctx?.saveGState()
        ctx?.setAlpha(frame.alpha)
        str.draw(at: NSPoint(x: x + (box - sz.width) / 2 + frame.dx, y: cy - sz.height / 2 + frame.dy))
        ctx?.restoreGState()
    }

    private static func drawRing(cx: CGFloat, cy: CGFloat, d: CGFloat, fraction: CGFloat, color: NSColor) {
        let lineWidth: CGFloat = 2.4
        let r = d / 2 - lineWidth / 2
        let center = NSPoint(x: cx, y: cy)

        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: r, startAngle: 0, endAngle: 360)
        track.lineWidth = lineWidth
        NSColor.tertiaryLabelColor.setStroke()
        track.stroke()

        let f = max(0, min(1, fraction))
        guard f > 0.001 else { return }
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: r, startAngle: 90, endAngle: 90 - 360 * f, clockwise: true)
        arc.lineWidth = lineWidth
        arc.lineCapStyle = .round
        color.setStroke()
        arc.stroke()
    }

    private static func drawText(_ s: String, font: NSFont, color: NSColor, x: CGFloat, cy: CGFloat) {
        let str = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
        let sz = str.size()
        str.draw(at: NSPoint(x: x, y: cy - sz.height / 2))
    }

    private static func drawSparkline(_ history: [Double], x: CGFloat, cy: CGFloat, w: CGFloat, h: CGFloat, color: NSColor) {
        guard history.count >= 2 else { return }
        let y0 = cy - h / 2
        let n = history.count
        let path = NSBezierPath()
        for (i, v) in history.enumerated() {
            let px = x + w * CGFloat(i) / CGFloat(n - 1)
            let py = y0 + h * CGFloat(max(0, min(100, v))) / 100
            if i == 0 { path.move(to: NSPoint(x: px, y: py)) } else { path.line(to: NSPoint(x: px, y: py)) }
        }
        path.lineWidth = 1.3
        path.lineJoinStyle = .round
        color.setStroke()
        path.stroke()
    }
}
