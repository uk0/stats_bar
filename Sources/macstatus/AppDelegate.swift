import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {

    private static let intervalKey = "refreshInterval"
    private static let authorURL = "https://github.com/uk0"

    private var statusItem: NSStatusItem!
    private let monitor = SystemMonitor()
    private var timer: Timer?
    private var interval: TimeInterval = 2.0

    // Detail rows in the dropdown menu (updated every tick).
    private let cpuItem = NSMenuItem()
    private let memItem = NSMenuItem()
    private let diskItem = NSMenuItem()

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

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "macstatus…"
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
        // .common keeps it firing while the menu is open (event tracking).
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: - Menu

    private func buildMenu() {
        let menu = NSMenu()

        let header = NSMenuItem(title: "系统监控 · macstatus", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        for item in [cpuItem, memItem, diskItem] {
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(makeIntervalMenu())

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

    @objc private func changeInterval(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? Double else { return }
        interval = seconds
        if let items = sender.menu?.items {
            for item in items { item.state = (item === sender) ? .on : .off }
        }
        UserDefaults.standard.set(seconds, forKey: Self.intervalKey)
        startTimer()
        update()
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
        let m = monitor.sample()
        statusItem.button?.attributedTitle = makeTitle(m)

        cpuItem.title = String(format: "CPU 占用：%5.1f%%", m.cpuUsage)
        memItem.title = String(
            format: "内存占用：%5.1f%%   (%@ / %@)",
            m.memoryUsage,
            memFormatter.string(fromByteCount: Int64(m.memUsedBytes)),
            memFormatter.string(fromByteCount: Int64(m.memTotalBytes))
        )
        diskItem.title = String(
            format: "磁盘剩余：%5.1f%%   (%@ 可用 / %@)",
            m.diskFree,
            diskFormatter.string(fromByteCount: m.diskFreeBytes),
            diskFormatter.string(fromByteCount: m.diskTotalBytes)
        )

        statusItem.button?.toolTip = String(
            format: "CPU 占用 %.1f%%  ·  内存占用 %.1f%%  ·  磁盘剩余 %.1f%%",
            m.cpuUsage, m.memoryUsage, m.diskFree
        )
    }

    /// Builds the colored, monospaced-digit status-bar title.
    private func makeTitle(_ m: Metrics) -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let result = NSMutableAttributedString()

        func segment(_ label: String, _ value: Double, color: NSColor, last: Bool = false) {
            let text = String(format: "%@ %3.0f%%%@", label, value, last ? "" : "  ")
            result.append(NSAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: color,
            ]))
        }

        segment("CPU", m.cpuUsage, color: usedColor(m.cpuUsage))
        segment("MEM", m.memoryUsage, color: usedColor(m.memoryUsage))
        segment("DISK", m.diskFree, color: freeColor(m.diskFree), last: true)
        return result
    }

    /// Higher = worse (CPU / memory).
    private func usedColor(_ pct: Double) -> NSColor {
        if pct >= 90 { return .systemRed }
        if pct >= 75 { return .systemOrange }
        return .labelColor
    }

    /// Lower = worse (free disk space).
    private func freeColor(_ pct: Double) -> NSColor {
        if pct <= 10 { return .systemRed }
        if pct <= 20 { return .systemOrange }
        return .labelColor
    }
}
