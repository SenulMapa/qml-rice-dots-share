// Desktop adapter over the shell's real services/ScreenRecService.qml
// (gpu-screen-recorder). Exposes impasto's RecorderService-shaped API
// (recording/display/subject/canAudio/toggle) for island/cards/RecorderCard
// .qml -- see that file's header for which parts of impasto's own
// RecorderModule.qml this shell's recorder genuinely backs.
//
// Real, honest gaps versus impasto's own RecorderService (not faked):
// this shell's ScreenRecService has no window-capture mode and no system-
// audio toggle -- gpu-screen-recorder is launched with a fixed argument set
// (see services/ScreenRecService.qml's beginRecording()). `canAudio` is
// therefore always false and `shapes` omits "window".

pragma Singleton

import QtQuick
import Quickshell
import "../../services" as Shell

Singleton {
    id: root

    readonly property bool recording: Shell.ScreenRecService.recording
    readonly property bool starting: Shell.ScreenRecService.starting
    readonly property string lastError: Shell.ScreenRecService.lastError
    readonly property string outputPath: Shell.ScreenRecService.outputPath
    readonly property string name: root.outputPath !== ""
        ? root.outputPath.slice(root.outputPath.lastIndexOf("/") + 1) : ""
    // Only "screen" is a real, wired capture mode here -- see the header.
    readonly property bool canAudio: false
    readonly property string subject: "Screen"
    readonly property string tool: "gpu-screen-recorder"

    function pad2(n: int): string { return n < 10 ? "0" + n : String(n) }
    readonly property string display: {
        const total = Math.max(0, Math.floor(Shell.ScreenRecService.elapsed))
        const m = Math.floor(total / 60)
        const s = total % 60
        return `${root.pad2(m)}:${root.pad2(s)}`
    }

    function toggle(): void {
        Shell.ScreenRecService.toggle()
    }
}
