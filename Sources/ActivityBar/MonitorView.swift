import SwiftUI

// MARK: - Tabs

enum ResourceTab: String, CaseIterable, Identifiable {
    case cpu     = "CPU"
    case memory  = "Memory"
    case disk    = "Disk"
    case network = "Network"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .cpu:     return "cpu"
        case .memory:  return "memorychip"
        case .disk:    return "internaldrive"
        case .network: return "network"
        }
    }

    var accentColor: Color {
        switch self {
        case .cpu:     return Color(nsColor: .systemBlue)
        case .memory:  return Color(nsColor: .systemPurple)
        case .disk:    return Color(nsColor: .systemGreen)
        case .network: return Color(nsColor: .systemOrange)
        }
    }
}

// MARK: - Root

struct MonitorView: View {
    @EnvironmentObject var store: StatsStore
    @State private var selected: ResourceTab = .cpu

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(selected: $selected)
                .frame(width: 148)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 700, height: 460)
    }

    @ViewBuilder
    private var detail: some View {
        switch selected {
        case .cpu:     CPUDetail()
        case .memory:  MemoryDetail()
        case .disk:    DiskDetail()
        case .network: NetworkDetail()
        }
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @Binding var selected: ResourceTab
    @EnvironmentObject var store: StatsStore

    var body: some View {
        VStack(spacing: 2) {
            ForEach(ResourceTab.allCases) { tab in
                SidebarRow(tab: tab, subtitle: subtitle(for: tab), isSelected: selected == tab) {
                    selected = tab
                }
            }
            Spacer()
            Divider()
            Button(action: openActivityMonitor) {
                Label("Activity Monitor", systemImage: "gauge.medium")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            Divider()
            Button(action: { NSApplication.shared.terminate(nil) }) {
                Label("Quit", systemImage: "power")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func openActivityMonitor() {
        NSWorkspace.shared.open(
            URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        )
    }

    private func subtitle(for tab: ResourceTab) -> String {
        switch tab {
        case .cpu:
            return String(format: "%.1f%%", store.cpuUser + store.cpuSystem)
        case .memory:
            return String(format: "%.2f GB", store.memUsedGB)
        case .disk:
            return String(format: "%.0f%%", store.diskUsedPercent)
        case .network:
            let peak = max(store.netInRate, store.netOutRate)
            return formatBytes(peak) + "/s"
        }
    }
}

private struct SidebarRow: View {
    let tab: ResourceTab
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? .white : tab.accentColor)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(tab.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isSelected ? .white : .primary)
                    Text(subtitle)
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundColor(isSelected ? .white.opacity(0.75) : .secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? tab.accentColor : Color.clear)
            )
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - CPU Detail

private let colCPU:  CGFloat = 75
private let colKind: CGFloat = 68
private let colPID:  CGFloat = 64
private let colUser: CGFloat = 90

private let darkBg   = Color(red: 0.10, green: 0.10, blue: 0.11)
private let darkCard = Color(red: 0.16, green: 0.16, blue: 0.17)

private struct CPUDetail: View {
    @EnvironmentObject var store: StatsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Compact stats header
            VStack(alignment: .leading, spacing: 8) {
                Text("CPU Usage")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(nsColor: .systemBlue))

                HStack(alignment: .top, spacing: 16) {
                    BigStat(value: String(format: "%.1f%%", store.cpuUser + store.cpuSystem),
                            label: "Total")
                    Spacer()
                    HStack(spacing: 8) {
                        StatCard(label: "User",   value: String(format: "%.1f%%", store.cpuUser),   color: .systemBlue)
                        StatCard(label: "System", value: String(format: "%.1f%%", store.cpuSystem), color: .systemRed)
                        StatCard(label: "Idle",   value: String(format: "%.1f%%", store.cpuIdle),   color: .systemGray)
                    }
                }

                SegmentBar(segments: [
                    (store.cpuUser   / 100, Color(nsColor: .systemBlue)),
                    (store.cpuSystem / 100, Color(nsColor: .systemRed)),
                ])
            }
            .padding(14)

            Divider()

            // Process table
            ProcessTable(processes: store.allProcesses, color: Color(nsColor: .systemBlue))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(darkBg)
    }
}

private struct ProcessTable: View {
    let processes: [SystemMonitor.ProcInfo]
    let color: Color

    var body: some View {
        VStack(spacing: 0) {
            // Column headers
            HStack(spacing: 0) {
                Text("Process Name")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("% CPU")
                    .frame(width: colCPU, alignment: .trailing)
                Text("Kind")
                    .frame(width: colKind, alignment: .trailing)
                Text("PID")
                    .frame(width: colPID, alignment: .trailing)
                Text("User")
                    .frame(width: colUser, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(14)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(processes) { proc in
                        ProcessRow(proc: proc)
                        Divider().opacity(0.4)
                    }
                }
            }
            .padding(.bottom, 12)
            .background(darkCard)
        }
    }
}

private struct ProcessRow: View {
    let proc: SystemMonitor.ProcInfo
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 0) {
            Text(proc.name)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(format: "%.1f", proc.cpuPercent))
                .frame(width: colCPU, alignment: .trailing)
                .foregroundColor(
                    proc.cpuPercent > 50 ? Color(nsColor: .systemRed) :
                    proc.cpuPercent > 20 ? Color(nsColor: .systemOrange) : .primary
                )

            Text(proc.kind)
                .frame(width: colKind, alignment: .trailing)
                .foregroundColor(.secondary)

            Text("\(proc.pid)")
                .frame(width: colPID, alignment: .trailing)
                .foregroundColor(.secondary)

            Text(proc.user)
                .lineLimit(1)
                .frame(width: colUser, alignment: .trailing)
                .foregroundColor(.secondary)
        }
        .font(.system(size: 11).monospacedDigit())
        .padding(6)
        .background(hovered ? Color(NSColor.selectedContentBackgroundColor).opacity(0.15) : Color.clear)
        .onHover { hovered = $0 }
    }
}

// MARK: - Memory Detail

private let colMem:     CGFloat = 90
private let colThreads: CGFloat = 68

private struct MemoryDetail: View {
    @EnvironmentObject var store: StatsStore

    private var byMemory: [SystemMonitor.ProcInfo] {
        store.allProcesses.sorted { $0.memoryBytes > $1.memoryBytes }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Compact stats header
            VStack(alignment: .leading, spacing: 8) {
                Text("Memory")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(nsColor: .systemPurple))

                HStack(alignment: .top, spacing: 16) {
                    BigStat(value: String(format: "%.2f GB", store.memUsedGB), label: "Used")
                    Spacer()
                    HStack(spacing: 8) {
                        StatCard(label: "Used",  value: String(format: "%.2f GB", store.memUsedGB),                    color: .systemPurple)
                        StatCard(label: "Free",  value: String(format: "%.2f GB", store.memTotalGB - store.memUsedGB), color: .systemGray)
                        StatCard(label: "Total", value: String(format: "%.2f GB", store.memTotalGB),                   color: .systemGray)
                    }
                }

                SegmentBar(segments: [
                    (store.memUsedPercent / 100, Color(nsColor: .systemPurple)),
                ])
            }
            .padding(14)

            Divider()

            // Process table
            MemoryProcessTable(processes: byMemory, color: Color(nsColor: .systemPurple))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(darkBg)
    }
}

private struct MemoryProcessTable: View {
    let processes: [SystemMonitor.ProcInfo]
    let color: Color

    var body: some View {
        VStack(spacing: 0) {
            // Column headers
            HStack(spacing: 0) {
                Text("Process Name")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Memory")
                    .frame(width: colMem, alignment: .trailing)
                Text("Threads")
                    .frame(width: colThreads, alignment: .trailing)
                Text("PID")
                    .frame(width: colPID, alignment: .trailing)
                Text("User")
                    .frame(width: colUser, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(14)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(processes) { proc in
                        MemoryProcessRow(proc: proc)
                        Divider().opacity(0.4)
                    }
                }
            }
            .padding(.bottom, 12)
            .background(darkCard)
        }
    }
}

private struct MemoryProcessRow: View {
    let proc: SystemMonitor.ProcInfo
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 0) {
            Text(proc.name)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(formatBytes(Double(proc.memoryBytes)))
                .frame(width: colMem, alignment: .trailing)

            Text("\(proc.threads)")
                .frame(width: colThreads, alignment: .trailing)
                .foregroundColor(.secondary)

            Text("\(proc.pid)")
                .frame(width: colPID, alignment: .trailing)
                .foregroundColor(.secondary)

            Text(proc.user)
                .lineLimit(1)
                .frame(width: colUser, alignment: .trailing)
                .foregroundColor(.secondary)
        }
        .font(.system(size: 11).monospacedDigit())
        .padding(6)
        .background(hovered ? Color(NSColor.selectedContentBackgroundColor).opacity(0.15) : Color.clear)
        .onHover { hovered = $0 }
    }
}

// MARK: - Disk Detail

private let colDiskRW: CGFloat = 90

private struct DiskDetail: View {
    @EnvironmentObject var store: StatsStore

    private var byDiskRead: [SystemMonitor.ProcInfo] {
        store.allProcesses.sorted { $0.diskBytesRead > $1.diskBytesRead }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Disk")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(nsColor: .systemGreen))

                HStack(alignment: .top, spacing: 16) {
                    BigStat(value: String(format: "%.0f%%", store.diskUsedPercent), label: "Used")
                    Spacer()
                    HStack(spacing: 8) {
                        StatCard(label: "Used",  value: String(format: "%.1f GB", store.diskUsedGB),                    color: .systemGreen)
                        StatCard(label: "Free",  value: String(format: "%.1f GB", store.diskTotalGB - store.diskUsedGB), color: .systemGray)
                        StatCard(label: "Total", value: String(format: "%.1f GB", store.diskTotalGB),                   color: .systemGray)
                    }
                }

                SegmentBar(segments: [
                    (store.diskUsedPercent / 100, Color(nsColor: .systemGreen)),
                ])
            }
            .padding(14)

            Divider()

            DiskProcessTable(processes: byDiskRead, color: Color(nsColor: .systemGreen))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(darkBg)
    }
}

private struct DiskProcessTable: View {
    let processes: [SystemMonitor.ProcInfo]
    let color: Color

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("Process Name")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Bytes Read")
                    .frame(width: colDiskRW, alignment: .trailing)
                Text("Bytes Write")
                    .frame(width: colDiskRW, alignment: .trailing)
                Text("PID")
                    .frame(width: colPID, alignment: .trailing)
                Text("User")
                    .frame(width: colUser, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(14)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(processes) { proc in
                        DiskProcessRow(proc: proc)
                        Divider().opacity(0.4)
                    }
                }
            }
            .padding(.bottom, 12)
            .background(darkCard)
        }
    }
}

private struct DiskProcessRow: View {
    let proc: SystemMonitor.ProcInfo
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 0) {
            Text(proc.name)
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(formatBytes(Double(proc.diskBytesRead)))
                .frame(width: colDiskRW, alignment: .trailing)
            Text(formatBytes(Double(proc.diskBytesWritten)))
                .frame(width: colDiskRW, alignment: .trailing)
            Text("\(proc.pid)")
                .frame(width: colPID, alignment: .trailing)
                .foregroundColor(.secondary)
            Text(proc.user)
                .lineLimit(1)
                .frame(width: colUser, alignment: .trailing)
                .foregroundColor(.secondary)
        }
        .font(.system(size: 11).monospacedDigit())
        .padding(6)
        .background(hovered ? Color(NSColor.selectedContentBackgroundColor).opacity(0.15) : Color.clear)
        .onHover { hovered = $0 }
    }
}

// MARK: - Network Detail

private let colConn: CGFloat = 90

private struct NetworkDetail: View {
    @EnvironmentObject var store: StatsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Network")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(nsColor: .systemOrange))

                HStack(spacing: 10) {
                    NetworkCard(direction: "Download", icon: "arrow.down.circle.fill",
                                color: .systemBlue,   rate: store.netInRate)
                    NetworkCard(direction: "Upload",   icon: "arrow.up.circle.fill",
                                color: .systemOrange, rate: store.netOutRate)
                }
            }
            .padding(14)

            Divider()

            NetworkProcessTable(processes: store.allProcesses, color: Color(nsColor: .systemOrange))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(darkBg)
    }
}

private struct NetworkCard: View {
    let direction: String
    let icon: String
    let color: NSColor
    let rate: Double

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(Color(nsColor: color))
            Text(formatRate(rate))
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
            Text(direction)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(darkCard)
        .cornerRadius(10)
    }
}

private struct NetworkProcessTable: View {
    let processes: [SystemMonitor.ProcInfo]
    let color: Color

    private var byConnections: [SystemMonitor.ProcInfo] {
        processes.sorted { $0.connections > $1.connections }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("Process Name")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Connections")
                    .frame(width: colConn, alignment: .trailing)
                Text("PID")
                    .frame(width: colPID, alignment: .trailing)
                Text("User")
                    .frame(width: colUser, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(14)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(byConnections) { proc in
                        NetworkProcessRow(proc: proc)
                        Divider().opacity(0.4)
                    }
                }
            }
            .padding(.bottom, 12)
            .background(darkCard)
        }
    }
}

private struct NetworkProcessRow: View {
    let proc: SystemMonitor.ProcInfo
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 0) {
            Text(proc.name)
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(proc.connections)")
                .frame(width: colConn, alignment: .trailing)
            Text("\(proc.pid)")
                .frame(width: colPID, alignment: .trailing)
                .foregroundColor(.secondary)
            Text(proc.user)
                .lineLimit(1)
                .frame(width: colUser, alignment: .trailing)
                .foregroundColor(.secondary)
        }
        .font(.system(size: 11).monospacedDigit())
        .padding(6)
        .background(hovered ? Color(NSColor.selectedContentBackgroundColor).opacity(0.15) : Color.clear)
        .onHover { hovered = $0 }
    }
}

// MARK: - Shared components

private struct DetailContainer<Content: View>: View {
    let title: String
    let color: Color
    let content: Content

    init(title: String, color: Color, @ViewBuilder content: () -> Content) {
        self.title = title
        self.color = color
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color)
            content
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct BigStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 32, weight: .light).monospacedDigit())
                .foregroundColor(.primary)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
}

private struct SegmentBar: View {
    let segments: [(Double, Color)]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(NSColor.separatorColor).opacity(0.3))
                HStack(spacing: 0) {
                    ForEach(Array(segments.enumerated()), id: \.0) { _, seg in
                        let w = max(0, geo.size.width * CGFloat(min(seg.0, 1)))
                        if w > 0 { seg.1.frame(width: w) }
                    }
                    Spacer(minLength: 0)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .frame(height: 10)
    }
}

private struct StatCard: View {
    let label: String
    let value: String
    let color: NSColor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Circle()
                    .fill(Color(nsColor: color))
                    .frame(width: 7, height: 7)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(darkCard)
        .cornerRadius(8)
    }
}

private struct LegendDot: View {
    let color: NSColor
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(Color(nsColor: color)).frame(width: 7, height: 7)
            Text(label).font(.system(size: 10)).foregroundColor(.secondary)
        }
    }
}
