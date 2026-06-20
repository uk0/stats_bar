import Foundation
import Darwin

/// One snapshot of the three metrics.
struct Metrics {
    /// CPU busy percentage (0...100), i.e. how much is in use.
    var cpuUsage: Double = 0
    /// Memory used percentage (0...100), Activity-Monitor style.
    var memoryUsage: Double = 0
    /// Disk *free* percentage (0...100), i.e. how much is left.
    var diskFree: Double = 0

    var memUsedBytes: UInt64 = 0
    var memTotalBytes: UInt64 = 0
    var diskFreeBytes: Int64 = 0
    var diskTotalBytes: Int64 = 0
}

/// Samples CPU / memory / disk using Mach + FileManager APIs.
///
/// CPU is a rate, so it needs two samples: the value returned is the busy
/// ratio over the interval since the previous `sample()` call. Call once to
/// prime the baseline, then read on each tick.
final class SystemMonitor {

    // Previous cumulative CPU ticks (bit patterns, wrap-safe).
    private var prevUser: UInt32 = 0
    private var prevSystem: UInt32 = 0
    private var prevIdle: UInt32 = 0
    private var prevNice: UInt32 = 0
    private var hasBaseline = false

    func sample() -> Metrics {
        var m = Metrics()
        m.cpuUsage = sampleCPU()
        let mem = sampleMemory()
        m.memoryUsage = mem.usage
        m.memUsedBytes = mem.used
        m.memTotalBytes = mem.total
        let disk = sampleDisk()
        m.diskFree = disk.freePct
        m.diskFreeBytes = disk.free
        m.diskTotalBytes = disk.total
        return m
    }

    // MARK: - CPU

    private func sampleCPU() -> Double {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let kr = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, intPtr, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }

        // cpu_ticks order: USER, SYSTEM, IDLE, NICE (already UInt32 / natural_t).
        let user = info.cpu_ticks.0
        let system = info.cpu_ticks.1
        let idle = info.cpu_ticks.2
        let nice = info.cpu_ticks.3

        defer {
            prevUser = user; prevSystem = system; prevIdle = idle; prevNice = nice
            hasBaseline = true
        }
        guard hasBaseline else { return 0 }

        let userDiff = Double(user &- prevUser)
        let systemDiff = Double(system &- prevSystem)
        let idleDiff = Double(idle &- prevIdle)
        let niceDiff = Double(nice &- prevNice)
        let total = userDiff + systemDiff + idleDiff + niceDiff
        guard total > 0 else { return 0 }

        let busy = (userDiff + systemDiff + niceDiff) / total * 100.0
        return min(max(busy, 0), 100)
    }

    // MARK: - Memory

    private func sampleMemory() -> (usage: Double, used: UInt64, total: UInt64) {
        let total = ProcessInfo.processInfo.physicalMemory

        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let kr = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return (0, 0, total) }

        let pageSize = UInt64(vm_kernel_page_size)
        let wired = UInt64(stats.wire_count)
        let compressed = UInt64(stats.compressor_page_count)
        let internalPages = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)

        // Activity Monitor "Memory Used" = App Memory + Wired + Compressed,
        // where App Memory = internal - purgeable.
        let appMemory = internalPages >= purgeable ? internalPages - purgeable : 0
        let used = (appMemory + wired + compressed) * pageSize
        let usage = total > 0 ? Double(used) / Double(total) * 100.0 : 0
        return (min(max(usage, 0), 100), used, total)
    }

    // MARK: - Disk

    private func sampleDisk() -> (freePct: Double, free: Int64, total: Int64) {
        // statfs() = the same view as `df`: real free space, not the
        // purgeable-inclusive "available for important usage" optimism.
        var st = statfs()
        guard statfs("/", &st) == 0 else { return (0, 0, 0) }
        let blockSize = UInt64(st.f_bsize)
        let total = UInt64(st.f_blocks) * blockSize
        let free = UInt64(st.f_bavail) * blockSize
        guard total > 0 else { return (0, 0, 0) }
        let freePct = Double(free) / Double(total) * 100.0
        return (min(max(freePct, 0), 100), Int64(free), Int64(total))
    }
}
