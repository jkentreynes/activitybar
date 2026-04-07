import Foundation

class StatsStore: ObservableObject {
    @Published var cpuUser: Double = 0
    @Published var cpuSystem: Double = 0
    @Published var cpuIdle: Double = 100

    @Published var memUsedGB: Double = 0
    @Published var memTotalGB: Double = 1
    @Published var memUsedPercent: Double = 0

    @Published var diskUsedGB: Double = 0
    @Published var diskTotalGB: Double = 1
    @Published var diskUsedPercent: Double = 0

    @Published var netInRate: Double = 0
    @Published var netOutRate: Double = 0

    @Published var processes: [SystemMonitor.ProcInfo] = []      // top 5 by memory (sidebar)
    @Published var allProcesses: [SystemMonitor.ProcInfo] = []   // all, sorted by CPU%
}
