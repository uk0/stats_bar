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
    exit(0)
}

// Menu-bar accessory app: no Dock icon, no main window.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
