import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private static let intervalKey = "refreshInterval"
    private static let authorURL = "https://github.com/uk0"

    private var statusItem: NSStatusItem!
    private let monitor = SystemMonitor()
    private var timer: Timer?
    private var interval: TimeInterval = 2.0

    // Cached once: the status-bar font never changes, so don't look it up per tick.
    private let titleFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)

    // Render state: skip the redraw when the displayed integers are unchanged,
    // and only format the heavy GB rows while the dropdown is actually open.
    private var lastTitleKey = ""
    private var lastMetrics = Metrics()
    private var menuOpen = false

    // Animated state face (😴 休息 / 🙂 工作中 / 🔥 火力全开 …).
    private static let animKey = "animationEnabled"
    private var animationEnabled = true
    private var currentState: MachineState?
    private var animFrames: [NSImage] = []
    private var animIndex = 0
    private var animTimer: Timer?
    private let stateItem = NSMenuItem()

    // Detail rows (refreshed only while the dropdown is open).
    private let cpuItem = NSMenuItem()
    private let memItem = NSMenuItem()
    private let diskItem = NSMenuItem()
    private let timeItem = NSMenuItem()

    // Totals are constant; format them once, then reuse the strings.
    private var memTotalString = ""
    private var diskTotalString = ""

    private let memFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useGB, .useMB]
        f.countStyle = .memory
        return f
    }()
    private let diskFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useGB, .useTB]
        f.countStyle = .file
        return f
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Restore the saved refresh interval (1...60s), default 2s.
        let saved = UserDefaults.standard.double(forKey: Self.intervalKey)
        if saved >= 1, saved <= 60 { interval = saved }
        if UserDefaults.standard.object(forKey: Self.animKey) != nil {
            animationEnabled = UserDefaults.standard.bool(forKey: Self.animKey)
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "macstatus…"
        statusItem.button?.imagePosition = .imageLeading
        buildMenu()

        // CPU is a rate, so the first read after priming would be 0. Prime the
        // baseline now, then take a quick first real reading shortly after.
        _ = monitor.sample()
        startTimer()
        let firstShot = Timer(timeInterval: 0.7, repeats: false) { [weak self] _ in
            self?.update()
        }
        RunLoop.main.add(firstShot, forMode: .common)
    }

    // MARK: - Timer

    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.update()
        }
        // Let the OS coalesce this wake-up with others to save energy.
        t.tolerance = interval * 0.25
        // .common keeps it firing while the menu is open (event tracking).
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: - Menu

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let header = NSMenuItem(title: "系统监控 · macstatus", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        stateItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(.separator())

        for item in [cpuItem, memItem, diskItem, timeItem] {
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(makeIntervalMenu())

        let anim = NSMenuItem(title: "动画效果", action: #selector(toggleAnimation(_:)), keyEquivalent: "")
        anim.target = self
        anim.state = animationEnabled ? .on : .off
        menu.addItem(anim)

        let login = NSMenuItem(title: "开机自动启动", action: #selector(toggleLoginItem(_:)), keyEquivalent: "")
        login.target = self
        login.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())

        let author = NSMenuItem(title: "作者：github.com/uk0", action: #selector(openAuthor), keyEquivalent: "")
        author.target = self
        menu.addItem(author)

        let quit = NSMenuItem(title: "退出 macstatus", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func makeIntervalMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "刷新间隔", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for seconds in [1.0, 2.0, 3.0, 5.0] {
            let item = NSMenuItem(
                title: "\(Int(seconds)) 秒",
                action: #selector(changeInterval(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = seconds
            item.state = (seconds == interval) ? .on : .off
            sub.addItem(item)
        }
        parent.submenu = sub
        return parent
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        menuOpen = true
        applyDetails(lastMetrics)   // show the latest sample immediately
    }

    func menuDidClose(_ menu: NSMenu) {
        menuOpen = false
    }

    // MARK: - Actions

    @objc private func changeInterval(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? Double else { return }
        interval = seconds
        if let items = sender.menu?.items {
            for item in items { item.state = (item === sender) ? .on : .off }
        }
        UserDefaults.standard.set(seconds, forKey: Self.intervalKey)
        startTimer()
    }

    @objc private func toggleLoginItem(_ sender: NSMenuItem) {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法修改开机启动项"
            alert.informativeText = "请先用 scripts/build_app.sh 打包，并从 dist/macstatus.app 启动后再设置。\n\n\(error.localizedDescription)"
            alert.runModal()
        }
        sender.state = (service.status == .enabled) ? .on : .off
    }

    @objc private func openAuthor() {
        if let url = URL(string: Self.authorURL) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Update

    private func update() {
        autoreleasepool {
            let m = monitor.sample()
            lastMetrics = m
            applyTitle(m)
            let st = MachineState.current(cpu: m.cpuUsage, mem: m.memoryUsage)
            if st != currentState { applyState(st) }
            if menuOpen { applyDetails(m) }
        }
    }

    // MARK: - State face

    /// Switches to a new mood: swap the pre-baked frames and (re)arm the
    /// animation timer at this state's pace. A static state leaves no timer.
    private func applyState(_ st: MachineState) {
        currentState = st
        animIndex = 0
        animFrames = StateFace.frames(for: st)
        statusItem.button?.image = animFrames.first
        stateItem.title = "状态：\(st.label) \(st.emoji)"

        animTimer?.invalidate()
        animTimer = nil
        if animationEnabled, animFrames.count > 1, let iv = st.animInterval {
            let t = Timer(timeInterval: iv, repeats: true) { [weak self] _ in self?.animTick() }
            RunLoop.main.add(t, forMode: .common)
            animTimer = t
        }
    }

    private func animTick() {
        guard animFrames.count > 1 else { return }
        animIndex = (animIndex + 1) % animFrames.count
        statusItem.button?.image = animFrames[animIndex]
    }

    @objc private func toggleAnimation(_ sender: NSMenuItem) {
        animationEnabled.toggle()
        sender.state = animationEnabled ? .on : .off
        UserDefaults.standard.set(animationEnabled, forKey: Self.animKey)
        if let st = currentState { applyState(st) }
    }

    /// Always-visible status-bar title. Skips the redraw entirely when the
    /// displayed integer percentages have not changed since last tick.
    private func applyTitle(_ m: Metrics) {
        let cpu = Int(m.cpuUsage.rounded())
        let mem = Int(m.memoryUsage.rounded())
        let disk = Int(m.diskFree.rounded())
        let time = Clock.now()
        // The clock ticks even when the metrics don't, so the minute is part of
        // the redraw key — otherwise a static machine would freeze the time.
        let key = "\(cpu)|\(mem)|\(disk)|\(time)"
        guard key != lastTitleKey else { return }
        lastTitleKey = key

        let result = NSMutableAttributedString()
        func segment(_ text: String, _ color: NSColor) {
            result.append(NSAttributedString(string: text, attributes: [
                .font: titleFont,
                .foregroundColor: color,
            ]))
        }
        segment(String(format: "CPU %3d%%  ", cpu), usedColor(cpu))
        segment(String(format: "MEM %3d%%  ", mem), usedColor(mem))
        segment(String(format: "DISK %3d%%", disk), freeColor(disk))
        segment("   \(time)", .secondaryLabelColor)

        let button = statusItem.button
        button?.attributedTitle = result
        button?.toolTip = "CPU 占用 \(cpu)%  ·  内存占用 \(mem)%  ·  磁盘剩余 \(disk)%  ·  北京时间 \(time)"
    }

    /// Dropdown detail rows with GB figures. Only invoked while the menu is
    /// open, so the ByteCountFormatter cost is paid only when actually visible.
    private func applyDetails(_ m: Metrics) {
        if memTotalString.isEmpty, m.memTotalBytes > 0 {
            memTotalString = memFormatter.string(fromByteCount: Int64(m.memTotalBytes))
        }
        if diskTotalString.isEmpty, m.diskTotalBytes > 0 {
            diskTotalString = diskFormatter.string(fromByteCount: m.diskTotalBytes)
        }
        cpuItem.title = String(format: "CPU 占用：%5.1f%%", m.cpuUsage)
        memItem.title = String(
            format: "内存占用：%5.1f%%   (%@ / %@)",
            m.memoryUsage, memFormatter.string(fromByteCount: Int64(m.memUsedBytes)), memTotalString
        )
        diskItem.title = String(
            format: "磁盘剩余：%5.1f%%   (%@ 可用 / %@)",
            m.diskFree, diskFormatter.string(fromByteCount: m.diskFreeBytes), diskTotalString
        )
        timeItem.title = "北京时间：\(Clock.now())"
    }

    /// Higher = worse (CPU / memory).
    private func usedColor(_ pct: Int) -> NSColor {
        if pct >= 90 { return .systemRed }
        if pct >= 75 { return .systemOrange }
        return .labelColor
    }

    /// Lower = worse (free disk space).
    private func freeColor(_ pct: Int) -> NSColor {
        if pct <= 10 { return .systemRed }
        if pct <= 20 { return .systemOrange }
        return .labelColor
    }
}
