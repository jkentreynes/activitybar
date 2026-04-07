import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let monitor = SystemMonitor()
    private let store = StatsStore()
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildStatusItem()
        buildPopover()
        warmUp()
        startRefresh()
    }

    // MARK: - Setup

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            btn.image = makeBarIcon(cpu: 0, mem: 0, disk: 0, net: 0)
            btn.imagePosition = .imageOnly
            btn.action = #selector(togglePopover)
            btn.target = self
        }
    }

    private func buildPopover() {
        let view = MonitorView().environmentObject(store)
        let vc = NSHostingController(rootView: view)
        vc.view.frame = NSRect(x: 0, y: 0, width: 700, height: 460)
        popover = NSPopover()
        popover.contentViewController = vc
        popover.contentSize = NSSize(width: 700, height: 460)
        popover.behavior = .transient
        popover.animates = true
    }

    private func warmUp() {
        _ = monitor.cpuStats()
        _ = monitor.networkRates()
    }

    // MARK: - Refresh

    private func startRefresh() {
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        timer?.fire()
    }

    private func refresh() {
        let cpu  = monitor.cpuStats()
        let mem  = monitor.memoryStats()
        let disk = monitor.diskStats()
        let (netIn, netOut) = monitor.networkRates()
        let allProcs = monitor.allProcesses()
        let procs = Array(allProcs.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(5))

        let netPeak = max(netIn, netOut)
        let netFrac = netPeak > 0
            ? min(1, log10(1 + netPeak / 10_000) / log10(1 + 10_000_000 / 10_000))
            : 0.0

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            // Update icon
            self.statusItem.button?.image = self.makeBarIcon(
                cpu:  cpu.total / 100,
                mem:  mem.usedPercent / 100,
                disk: disk.usedPercent / 100,
                net:  netFrac
            )

            // Update store (triggers SwiftUI refresh)
            self.store.cpuUser    = cpu.user
            self.store.cpuSystem  = cpu.system
            self.store.cpuIdle    = cpu.idle
            self.store.memUsedGB  = mem.usedGB
            self.store.memTotalGB = mem.totalGB
            self.store.memUsedPercent = mem.usedPercent
            self.store.diskUsedGB  = disk.usedGB
            self.store.diskTotalGB = disk.totalGB
            self.store.diskUsedPercent = disk.usedPercent
            self.store.netInRate  = netIn
            self.store.netOutRate = netOut
            self.store.processes    = procs
            self.store.allProcesses = allProcs
        }
    }

    // MARK: - Icon

    private func makeBarIcon(cpu: Double, mem: Double, disk: Double, net: Double) -> NSImage {
        let barW: CGFloat = 4
        let gap: CGFloat  = 2
        let maxH: CGFloat = 12
        let imgW: CGFloat = barW * 4 + gap * 3 + 4
        let imgH: CGFloat = 16

        let image = NSImage(size: NSSize(width: imgW, height: imgH))
        image.lockFocus()

        let fractions = [cpu, mem, disk, net].map { min(max($0, 0), 1) }
        let yBase: CGFloat = (imgH - maxH) / 2

        for (idx, fraction) in fractions.enumerated() {
            let x = CGFloat(idx) * (barW + gap) + 2
            let fillH = max(2, maxH * CGFloat(fraction))
            let trackRect = NSRect(x: x, y: yBase, width: barW, height: maxH)
            let fillRect  = NSRect(x: x, y: yBase, width: barW, height: fillH)

            // Track: faint fill + solid border
            let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: 1.5, yRadius: 1.5)
            NSColor.black.withAlphaComponent(0.12).setFill()
            trackPath.fill()
            NSColor.black.withAlphaComponent(0.55).setStroke()
            trackPath.lineWidth = 1.0
            trackPath.stroke()

            // Fill: solid fill + solid border
            let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 1.5, yRadius: 1.5)
            NSColor.black.setFill()
            fillPath.fill()
            NSColor.black.setStroke()
            fillPath.lineWidth = 1.0
            fillPath.stroke()
        }

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    // MARK: - Actions

    @objc private func togglePopover() {
        guard let btn = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
