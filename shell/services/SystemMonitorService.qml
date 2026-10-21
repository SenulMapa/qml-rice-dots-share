pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * SystemMonitorService -- polls /proc, df, and hwmon for CPU/memory/disk
 * load plus CPU temperature, backing widgets/SystemMonitorWidget.qml. ii
 * has no direct equivalent singleton (its resource readouts live inline in
 * a few different bar/sidebar widgets); this is a from-scratch minimal
 * service in the same idle-cheap spirit as PerformanceService.qml -- one
 * shared Process/poll for however many SystemMonitorWidget instances
 * exist, not one per widget.
 *
 * CPU% is derived from the delta between two /proc/stat samples (the
 * standard technique -- a single snapshot only gives a cumulative total
 * since boot, not a current load), polled every 2s. Memory% comes straight
 * from /proc/meminfo's MemTotal/MemAvailable, no delta needed. Disk% is
 * `df -k /`'s used/total. CPU temperature reads the first hwmon device
 * named k10temp (AMD) or coretemp (Intel) -- neither this machine nor any
 * target machine is guaranteed to expose /sys/class/thermal zones (this
 * one has none, only cooling_device entries with no matching zones), so
 * hwmon is the reliable source; tempAvailable is false and the widget
 * omits the row entirely when no such sensor exists.
 */
QtObject {
    id: root

    property real cpuPercent: 0
    property real memPercent: 0
    property real diskPercent: 0
    property real tempCelsius: 0
    property bool tempAvailable: false

    property var _prevIdle: 0
    property var _prevTotal: 0

    function _parseStat(text: string): void {
        const line = text.split("\n").find(l => l.startsWith("cpu "))
        if (!line)
            return
        const fields = line.trim().split(/\s+/).slice(1).map(Number)
        const idle = (fields[3] || 0) + (fields[4] || 0)
        const total = fields.reduce((a, b) => a + b, 0)
        const deltaIdle = idle - root._prevIdle
        const deltaTotal = total - root._prevTotal
        if (root._prevTotal > 0 && deltaTotal > 0)
            root.cpuPercent = Math.max(0, Math.min(100,
                100 * (1 - deltaIdle / deltaTotal)))
        root._prevIdle = idle
        root._prevTotal = total
    }

    function _parseMeminfo(text: string): void {
        const lines = text.split("\n")
        const get = key => {
            const line = lines.find(l => l.startsWith(key + ":"))
            return line ? parseFloat(line.split(/\s+/)[1]) : 0
        }
        const total = get("MemTotal")
        const available = get("MemAvailable")
        if (total > 0)
            root.memPercent = Math.max(0, Math.min(100,
                100 * (1 - available / total)))
    }

    function _parseDisk(text: string): void {
        // `df -k /`'s second line: filesystem, 1K-blocks, used, available,
        // use%, mounted-on -- used/(used+available) rather than trusting
        // the use% column's own rounding.
        const line = text.trim().split("\n")[1]
        if (!line)
            return
        const fields = line.trim().split(/\s+/)
        const usedKb = parseFloat(fields[2])
        const availKb = parseFloat(fields[3])
        if (usedKb + availKb > 0)
            root.diskPercent = Math.max(0, Math.min(100,
                100 * usedKb / (usedKb + availKb)))
    }

    function _parseTemp(text: string): void {
        const raw = parseFloat(text.trim())
        if (Number.isFinite(raw) && raw > 0) {
            root.tempCelsius = raw / 1000
            root.tempAvailable = true
        } else {
            root.tempAvailable = false
        }
    }

    // One shell invocation per poll, each section delimited so the parsers
    // above can split on a marker instead of guessing byte offsets. The
    // hwmon probe walks every hwmon* device looking for k10temp/coretemp's
    // temp1_input -- printing nothing (empty TEMP section) when neither
    // exists, which _parseTemp treats as "unavailable".
    property Process pollProcess: Process {
        command: ["sh", "-c",
            "cat /proc/stat; echo ===MEM===; cat /proc/meminfo; " +
            "echo ===DISK===; df -k /; echo ===TEMP===; " +
            "for f in /sys/class/hwmon/hwmon*; do " +
            "n=$(cat \"$f/name\" 2>/dev/null); " +
            "if [ \"$n\" = k10temp ] || [ \"$n\" = coretemp ]; then " +
            "cat \"$f/temp1_input\" 2>/dev/null; break; fi; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const memSplit = text.split("===MEM===")
                if (memSplit.length < 2)
                    return
                root._parseStat(memSplit[0])
                const diskSplit = memSplit[1].split("===DISK===")
                if (diskSplit.length < 2)
                    return
                root._parseMeminfo(diskSplit[0])
                const tempSplit = diskSplit[1].split("===TEMP===")
                if (tempSplit.length < 2)
                    return
                root._parseDisk(tempSplit[0])
                root._parseTemp(tempSplit[1])
            }
        }
    }

    property Timer pollTimer: Timer {
        interval: 2000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.pollProcess.running = true
    }
}
