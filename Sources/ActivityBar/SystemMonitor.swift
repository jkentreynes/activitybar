import Foundation
import Darwin

struct CPUStats {
    let user: Double
    let system: Double
    let idle: Double
    var total: Double { user + system }
}

struct MemoryStats {
    let usedBytes: UInt64
    let totalBytes: UInt64
    var usedGB: Double { Double(usedBytes) / 1_073_741_824 }
    var totalGB: Double { Double(totalBytes) / 1_073_741_824 }
    var usedPercent: Double { totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) * 100 : 0 }
}

struct DiskStats {
    let usedBytes: Int64
    let totalBytes: Int64
    var usedGB: Double { Double(usedBytes) / 1_073_741_824 }
    var totalGB: Double { Double(totalBytes) / 1_073_741_824 }
    var usedPercent: Double { totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) * 100 : 0 }
}

struct NetworkStats {
    let bytesIn: UInt64
    let bytesOut: UInt64
}

class SystemMonitor {
    private var prevCPUInfo: processor_info_array_t?
    private var prevNumCPUInfo: mach_msg_type_number_t = 0
    private var prevNetIn: UInt64 = 0
    private var prevNetOut: UInt64 = 0
    private var lastNetSample = Date()

    // Per-process CPU tracking
    private var prevProcTimes: [Int32: UInt64] = [:]  // pid -> Mach ticks (pti_total_user + pti_total_system)
    private var prevProcSampleTicks: UInt64 = mach_absolute_time()
    private var userCache: [uid_t: String] = [:]

    // Number of logical CPUs (for normalising CPU%)
    private let logicalCPUCount: Double = {
        var count: uint = 0
        var size = MemoryLayout<uint>.size
        sysctlbyname("hw.logicalcpu", &count, &size, nil, 0)
        return Double(max(1, count))
    }()

    // MARK: - CPU

    func cpuStats() -> CPUStats {
        var numCPUs: natural_t = 0
        var newInfo: processor_info_array_t?
        var newCount: mach_msg_type_number_t = 0

        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUs, &newInfo, &newCount)
        guard result == KERN_SUCCESS, let newInfo else {
            return CPUStats(user: 0, system: 0, idle: 100)
        }

        // Snapshot old pointers before overwriting, then free them after computation.
        let oldInfo = prevCPUInfo
        let oldCount = prevNumCPUInfo
        defer {
            if let old = oldInfo {
                vm_deallocate(mach_task_self_, vm_address_t(bitPattern: old), vm_size_t(oldCount))
            }
        }

        // Store new as previous for next call.
        prevCPUInfo = newInfo
        prevNumCPUInfo = newCount

        var totalUser: Int64 = 0
        var totalSystem: Int64 = 0
        var totalIdle: Int64 = 0
        var totalNice: Int64 = 0

        for i in 0..<Int(numCPUs) {
            let base = Int(CPU_STATE_MAX) * i
            let user   = Int64(bitPattern: UInt64(bitPattern: Int64(newInfo[base + Int(CPU_STATE_USER)])))
            let system = Int64(bitPattern: UInt64(bitPattern: Int64(newInfo[base + Int(CPU_STATE_SYSTEM)])))
            let idle   = Int64(bitPattern: UInt64(bitPattern: Int64(newInfo[base + Int(CPU_STATE_IDLE)])))
            let nice   = Int64(bitPattern: UInt64(bitPattern: Int64(newInfo[base + Int(CPU_STATE_NICE)])))

            if let old = oldInfo {
                totalUser   += max(0, user   - Int64(old[base + Int(CPU_STATE_USER)]))
                totalSystem += max(0, system - Int64(old[base + Int(CPU_STATE_SYSTEM)]))
                totalIdle   += max(0, idle   - Int64(old[base + Int(CPU_STATE_IDLE)]))
                totalNice   += max(0, nice   - Int64(old[base + Int(CPU_STATE_NICE)]))
            } else {
                totalUser += user; totalSystem += system
                totalIdle += idle; totalNice   += nice
            }
        }

        let total = Double(totalUser + totalSystem + totalIdle + totalNice)
        guard total > 0 else { return CPUStats(user: 0, system: 0, idle: 100) }

        return CPUStats(
            user: Double(totalUser + totalNice) / total * 100,
            system: Double(totalSystem) / total * 100,
            idle: Double(totalIdle) / total * 100
        )
    }

    // MARK: - Memory

    func memoryStats() -> MemoryStats {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result: kern_return_t = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        let pageSize = UInt64(vm_page_size)
        let totalPages = Foundation.ProcessInfo.processInfo.physicalMemory / pageSize

        guard result == KERN_SUCCESS else {
            return MemoryStats(usedBytes: 0, totalBytes: Foundation.ProcessInfo.processInfo.physicalMemory)
        }

        let active = UInt64(stats.active_count)
        let wired = UInt64(stats.wire_count)
        let compressed = UInt64(stats.compressor_page_count)
        let usedPages = active + wired + compressed

        return MemoryStats(
            usedBytes: min(usedPages, totalPages) * pageSize,
            totalBytes: Foundation.ProcessInfo.processInfo.physicalMemory
        )
    }

    // MARK: - Disk

    func diskStats(path: String = "/") -> DiskStats {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: path),
              let total = attrs[.systemSize] as? Int64,
              let free = attrs[.systemFreeSize] as? Int64 else {
            return DiskStats(usedBytes: 0, totalBytes: 0)
        }
        return DiskStats(usedBytes: total - free, totalBytes: total)
    }

    // MARK: - Network

    func networkRates() -> (inRate: Double, outRate: Double) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return (0, 0)
        }
        defer { freeifaddrs(ifaddr) }

        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0

        var ptr = firstAddr
        while true {
            let addr = ptr.pointee
            if addr.ifa_addr.pointee.sa_family == UInt8(AF_LINK) {
                let name = String(cString: addr.ifa_name)
                // Skip loopback
                if !name.hasPrefix("lo") {
                    if let data = addr.ifa_data {
                        let ifData = data.assumingMemoryBound(to: if_data.self).pointee
                        totalIn += UInt64(ifData.ifi_ibytes)
                        totalOut += UInt64(ifData.ifi_obytes)
                    }
                }
            }
            if addr.ifa_next == nil { break }
            ptr = addr.ifa_next!
        }

        let now = Date()
        let elapsed = now.timeIntervalSince(lastNetSample)
        lastNetSample = now

        let inRate: Double
        let outRate: Double

        if prevNetIn == 0 && prevNetOut == 0 {
            inRate = 0
            outRate = 0
        } else {
            let dIn = totalIn >= prevNetIn ? totalIn - prevNetIn : 0
            let dOut = totalOut >= prevNetOut ? totalOut - prevNetOut : 0
            inRate = elapsed > 0 ? Double(dIn) / elapsed : 0
            outRate = elapsed > 0 ? Double(dOut) / elapsed : 0
        }

        prevNetIn = totalIn
        prevNetOut = totalOut

        return (inRate, outRate)
    }

    // MARK: - Processes

    struct ProcInfo: Identifiable {
        let pid: Int32
        let name: String
        let cpuPercent: Double
        let memoryBytes: UInt64
        let threads: Int32
        let kind: String        // "Apple" or "Intel"
        let user: String
        let diskBytesRead: UInt64
        let diskBytesWritten: UInt64
        let connections: Int    // open socket FD count
        var id: Int32 { pid }
    }

    /// Returns all running processes sorted by CPU% descending.
    func allProcesses() -> [ProcInfo] {
        var mib = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        sysctl(&mib, 4, nil, &size, nil, 0)
        let count = size / MemoryLayout<kinfo_proc>.size
        var procList = [kinfo_proc](repeating: kinfo_proc(), count: count)
        sysctl(&mib, 4, &procList, &size, nil, 0)

        let now = mach_absolute_time()
        let elapsedTicks = now > prevProcSampleTicks ? now - prevProcSampleTicks : 1
        prevProcSampleTicks = now

        var newTimes: [Int32: UInt64] = [:]
        var procs: [ProcInfo] = []

        for i in 0..<count {
            let p = procList[i]
            let pid = p.kp_proc.p_pid
            guard pid > 0 else { continue }

            let name = withUnsafeBytes(of: p.kp_proc.p_comm) { bytes -> String in
                String(cString: Array(bytes.bindMemory(to: CChar.self)) + [0])
            }
            guard !name.isEmpty else { continue }

            var taskInfo = proc_taskinfo()
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo,
                               Int32(MemoryLayout<proc_taskinfo>.size)) > 0 else { continue }

            let totalNs = taskInfo.pti_total_user + taskInfo.pti_total_system
            newTimes[pid] = totalNs

            // Real-time CPU%: delta ns / elapsed ns / logical CPUs * 100
            let cpuPercent: Double
            if let prev = prevProcTimes[pid], elapsedTicks > 0 {
                let delta = totalNs >= prev ? totalNs - prev : 0
                cpuPercent = min(logicalCPUCount * 100,
                                 Double(delta) / Double(elapsedTicks) * 100)
            } else {
                cpuPercent = 0
            }

            // Kind: P_TRANSLATED (0x20000) is set for Rosetta processes on Apple Silicon
            let isRosetta = (p.kp_proc.p_flag & 0x20000) != 0
            let kind = isRosetta ? "Intel" : "Apple"

            // User: look up from UID, with cache
            let uid = p.kp_eproc.e_ucred.cr_uid
            let user = cachedUser(uid: uid)

            // Disk I/O: cumulative bytes read/written since process start
            // proc_pid_rusage does copyout() directly to the address passed as `buffer`,
            // so we pass the address of the output struct cast to the expected pointer type.
            var diskRead: UInt64 = 0
            var diskWritten: UInt64 = 0
            var rusageInfo = rusage_info_v4()
            let diskOk: Int32 = withUnsafeMutablePointer(to: &rusageInfo) { ptr in
                UnsafeMutableRawPointer(ptr).withMemoryRebound(
                    to: rusage_info_t?.self, capacity: 1
                ) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
            }
            if diskOk == 0 {
                diskRead    = rusageInfo.ri_diskio_bytesread
                diskWritten = rusageInfo.ri_diskio_byteswritten
            }

            procs.append(ProcInfo(
                pid: pid,
                name: name,
                cpuPercent: cpuPercent,
                memoryBytes: taskInfo.pti_resident_size,
                threads: taskInfo.pti_threadnum,
                kind: kind,
                user: user,
                diskBytesRead: diskRead,
                diskBytesWritten: diskWritten,
                connections: socketCount(for: pid)
            ))
        }

        prevProcTimes = newTimes
        return procs.sorted { $0.cpuPercent > $1.cpuPercent }
    }

    /// Top N processes by memory for the sidebar summary.
    func topProcesses(count: Int = 5) -> [ProcInfo] {
        Array(allProcesses().sorted { $0.memoryBytes > $1.memoryBytes }.prefix(count))
    }

    // Count open socket file descriptors for a process.
    // PROX_FDTYPE_SOCKET == 2 (from <sys/proc_info.h>)
    private func socketCount(for pid: Int32) -> Int {
        let maxFDs = 512
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: maxFDs)
        let bufSize = Int32(MemoryLayout<proc_fdinfo>.size * maxFDs)
        let ret = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, bufSize)
        guard ret > 0 else { return 0 }
        let n = Int(ret) / MemoryLayout<proc_fdinfo>.size
        return fds.prefix(n).filter { $0.proc_fdtype == 2 }.count
    }

    private func cachedUser(uid: uid_t) -> String {
        if let cached = userCache[uid] { return cached }
        let name: String
        if let pw = getpwuid(uid) {
            name = String(cString: pw.pointee.pw_name)
        } else {
            name = "\(uid)"
        }
        userCache[uid] = name
        return name
    }
}

// MARK: - Formatting helpers

func formatBytes(_ bytes: Double) -> String {
    switch bytes {
    case ..<1_024: return String(format: "%.0f B", bytes)
    case ..<1_048_576: return String(format: "%.1f KB", bytes / 1_024)
    case ..<1_073_741_824: return String(format: "%.1f MB", bytes / 1_048_576)
    default: return String(format: "%.2f GB", bytes / 1_073_741_824)
    }
}

func formatRate(_ bytesPerSec: Double) -> String {
    formatBytes(bytesPerSec) + "/s"
}
