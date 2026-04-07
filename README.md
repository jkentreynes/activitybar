# ActivityBar

A lightweight macOS menu bar app that shows live CPU, Memory, Disk, and Network stats with per-process detail views.

## Requirements

- macOS 13 or later
- Xcode Command Line Tools (`xcode-select --install`)

---

## Installation

### 1. Build the app

```bash
cd /<source code location>/activitybar
bash build.sh
```

This produces `ActivityBar.app` in the project directory.

### 2. Move to Applications

```bash
cp -R ActivityBar.app /Applications/ActivityBar.app
```

### 3. Launch

```bash
open /Applications/ActivityBar.app
```

Or double-click **ActivityBar.app** in Finder.

> **First launch:** macOS may show a security prompt since the app is not notarized. Go to **System Settings → Privacy & Security** and click **Open Anyway**.

### 4. Launch at login (optional)

1. Open **System Settings → General → Login Items**
2. Click **+** under "Open at Login"
3. Select `/Applications/ActivityBar.app`

---

## Redeploying after updates

Run this single command from the project directory — it stops the running instance, rebuilds, reinstalls, and relaunches:

```bash
pkill ActivityBar 2>/dev/null; bash build.sh && cp -R ActivityBar.app /Applications/ActivityBar.app && open /Applications/ActivityBar.app
```

Or step by step:

```bash
# 1. Stop the running instance
pkill ActivityBar

# 2. Rebuild
bash build.sh

# 3. Replace the installed app
cp -R ActivityBar.app /Applications/ActivityBar.app

# 4. Launch
open /Applications/ActivityBar.app
```

---

## Project structure

```
activitybar/
├── build.sh                        # Build script — compiles and packages ActivityBar.app
├── Package.swift                   # Swift Package Manager manifest
└── Sources/ActivityBar/
    ├── main.swift                  # Entry point
    ├── AppDelegate.swift           # Menu bar icon, popover, refresh timer
    ├── SystemMonitor.swift         # CPU, memory, disk, network, process data
    ├── StatsStore.swift            # ObservableObject that drives the SwiftUI views
    └── MonitorView.swift           # SwiftUI popover UI (sidebar + detail views)
```

## Detail views

| Tab | Columns |
|-----|---------|
| CPU | Process Name, % CPU, Kind, PID, User |
| Memory | Process Name, Memory, Threads, PID, User |
| Disk | Process Name, Bytes Read, Bytes Written, PID, User |
| Network | Process Name, Connections, PID, User |
