pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Per-app power from parity-ledger ($XDG_RUNTIME_DIR/parity/ledger.json,
// rewritten every ~5 s by the user daemon). Zero work unless `active`:
// the FileView path is empty (no inotify watch, no reads) and the stale
// timer is stopped. The consumer (components/EnergyList.qml, shown in the
// island's energy satellite) binds `active` to "satellite actually open" -- NOT to opacity/visible-of-an-
// ancestor, which stays true while faded out (the class of battery-drain
// bug BatteryOSD and the old dashboard's VinylDisc both had).
QtObject {
    id: root

    property bool active: false

    property string ledgerPath:
        (Quickshell.env("XDG_RUNTIME_DIR") || "") + "/parity/ledger.json"
    // Daemon writes every 5 s; older than this means it is not running.
    readonly property real staleSeconds: 20

    property bool available: false
    property string source: "none"
    property var totalW: null
    property var estHours: null
    property bool onAc: false
    // [{name, w (number|null), cpuPct, gpuPct, state, isPlatform}]: at most 8 app rows
    // in ledger order, then the "screen & platform" row LAST (when present).
    property var apps: []
    // The ledger's "screen & platform" row (null when absent).
    property var screenPlatformW: null
    readonly property bool hasWatts: totalW !== null && totalW !== undefined

    function reset(): void {
        available = false
        source = "none"
        totalW = null
        estHours = null
        apps = []
        screenPlatformW = null
    }

    function parse(text: string): void {
        try {
            const d = JSON.parse(text)
            if (!d || typeof d !== "object" || !Array.isArray(d.apps))
                throw new Error("bad ledger")
            if (typeof d.t === "number" && Date.now() / 1000 - d.t > staleSeconds)
                throw new Error("stale ledger")
            const rows = []
            let platformRow = null
            for (const a of d.apps) {
                const w = typeof a.w === "number" ? a.w : null
                const isPlatform = String(a.name).toLowerCase() === "screen & platform"
                const row = {
                    name: String(a.name),
                    w: w,
                    cpuPct: Number(a.cpu_pct) || 0,
                    gpuPct: Number(a.gpu_pct) || 0,
                    state: String(a.state || "unknown"),
                    isPlatform: isPlatform
                }
                // The platform row would otherwise crowd real apps out of the top 8
                // (it is usually the largest); it is pinned last instead.
                if (isPlatform)
                    platformRow = row
                else if (rows.length < 8)
                    rows.push(row)
            }
            const platform = platformRow ? platformRow.w : null
            if (platformRow)
                rows.push(platformRow)
            source = String(d.source || "none")
            onAc = !!d.on_ac
            totalW = typeof d.total_w === "number" ? d.total_w : null
            estHours = typeof d.est_hours === "number" ? d.est_hours : null
            screenPlatformW = platform
            apps = rows
            available = true
        } catch (e) {
            reset()
        }
    }

    onActiveChanged: if (!active) reset()

    readonly property FileView file: FileView {
        path: root.active ? root.ledgerPath : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.parse(text())
        onLoadFailed: root.reset()
    }

    // Catches a daemon that died: the file stops changing, so no event fires.
    readonly property Timer staleTimer: Timer {
        interval: 10000
        repeat: true
        running: root.active && root.available
        onTriggered: root.file.reload()
    }
}
