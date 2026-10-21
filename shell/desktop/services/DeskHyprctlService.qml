pragma Singleton
import QtQuick
import Quickshell.Io

/**
 * DeskHyprctlService -- a thin fire-and-forget wrapper over
 * `hyprctl keyword <key> <value>`, for the impasto-settings-full port's
 * live-apply controls (Input's Hyprland input options and pointer cursor,
 * Displays' monitor scale/position, Appearance's window-animation preset).
 *
 * Follows services/NightLightService.qml's own established pattern for
 * shelling out to hyprctl (one Process per call, queued so a fast double
 * click cannot race two writes). "hyprctl keyword" is a RUNTIME-ONLY
 * change: this shell's Hyprland config is Lua (hypr/modules/*.lua per the
 * impasto-settings-full brief), and nothing here writes to it, so every
 * value applied through this service reverts on the next `hyprctl reload`
 * unless the matching Lua module also sets it -- exactly the same
 * runtime-vs-persisted split MonitorCanvas.qml's own header already
 * documents for its read-only monitor plate. `setCursor` is the one
 * exception that is NOT a keyword: `hyprctl setcursor <theme> <size>` is
 * its own hyprctl subcommand (size-only, no theme change), used by
 * Input's cursor-size slider.
 */
QtObject {
    id: root

    property var queue: []
    property bool busy: false

    // key: e.g. "input:sensitivity", "monitor", "animation", "bezier"
    // value: the keyword's argument string, e.g. "0.3" or
    //        "eDP-1,1920x1080@60,0x0,1"
    function apply(key: string, value: string): void {
        root.queue.push(["keyword", key, value])
        root.pump()
    }

    // theme: the XCursor theme already in effect (env XCURSOR_THEME, or
    // whatever GTK/Hyprland already resolved) -- this never changes the
    // theme, only re-asserts it at a new size, which is what `hyprctl
    // setcursor` requires as its first argument regardless.
    function setCursorSize(theme: string, size: int): void {
        root.queue.push(["setcursor", theme, String(size)])
        root.pump()
    }

    function pump(): void {
        if (root.busy || root.queue.length === 0)
            return
        const next = root.queue.shift()
        root.busy = true
        runner.command = ["hyprctl"].concat(next)
        runner.running = true
    }

    property Process runner: Process {
        running: false
        onExited: (exitCode, exitStatus) => {
            root.busy = false
            if (exitCode !== 0)
                console.warn("qml-rice DeskHyprctlService: hyprctl keyword failed:",
                    runner.command.join(" "))
            root.pump()
        }
    }
}
