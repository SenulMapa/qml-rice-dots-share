pragma Singleton
import QtQuick
import Quickshell.Io
import "../core"

/**
 * NightLightService - a thin wrapper over hyprsunset's own IPC.
 *
 * hyprsunset owns the actual colour temperature; this service only reads it
 * (`hyprctl hyprsunset temperature`, no argument) and can set it
 * (`hyprctl hyprsunset temperature <K>` to warm it, `hyprctl hyprsunset
 * identity` to disable it). There is no daemon of our own to keep in sync --
 * refreshing after every write is what keeps `temperature`/`enabled` honest.
 */
QtObject {
    id: root

    property bool available: false
    property int temperature: 6500

    readonly property bool enabled: available && temperature < 5500

    function refresh(): void {
        if (!queryProcess.running)
            queryProcess.running = true
    }

    function parseTemperature(text: string): void {
        const match = text.match(/\d+(?:\.\d+)?/)
        if (!match) {
            root.available = false
            return
        }
        root.temperature = Math.round(Number(match[0]))
        root.available = true
    }

    function setEnabled(value: bool): void {
        if (!root.available || setProcess.running)
            return
        setProcess.command = value
            ? ["hyprctl", "hyprsunset", "temperature", String(Config.nightLight.warmTemperature)]
            : ["hyprctl", "hyprsunset", "identity"]
        setProcess.running = true
    }

    function toggle(): void {
        setEnabled(!root.enabled)
    }

    property Process queryProcess: Process {
        command: ["hyprctl", "hyprsunset", "temperature"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.parseTemperature(text)
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                root.available = false
        }
    }

    property Process setProcess: Process {
        running: false
        onExited: (exitCode, exitStatus) => root.refresh()
    }

    property Timer pollTimer: Timer {
        interval: 10000
        repeat: true
        running: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: refresh()
}
