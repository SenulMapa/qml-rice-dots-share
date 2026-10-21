// Desktop adapter over the shell's real services/AudioService.qml (PipeWire
// default sink). Exposes impasto's AudioService-shaped API (icon/muted/
// volume as an 0-100 int) for the volume module's faces.

pragma Singleton

import QtQuick
import Quickshell
import "../../services" as Shell

Singleton {
    id: root

    readonly property bool available: Shell.AudioService.available
    readonly property int volume: Shell.AudioService.volumePercent
    readonly property bool muted: Shell.AudioService.muted

    readonly property string icon: {
        if (root.muted || root.volume === 0)
            return "󰝟"
        if (root.volume < 34)
            return "󰕿"
        if (root.volume < 67)
            return "󰖀"
        return "󰕾"
    }

    function setVolume(percent: int): void {
        Shell.AudioService.setVolume(percent)
    }

    function toggleMute(): void {
        if (Shell.AudioService.sink)
            Shell.AudioService.sink.audio.muted = !root.muted
    }

    // impasto's VolumeModule detail card (island/cards/VolumeCard.qml) also
    // has a "Mic" pill next to "Mute" -- impasto's own AudioService exposes
    // this as `sourceMuted`/`toggleSourceMute`; this shell's real source
    // (microphone) state already exists on services/AudioService.qml as
    // microphoneMuted/toggleMicrophoneMute, just under different names.
    readonly property bool sourceMuted: Shell.AudioService.microphoneMuted

    function toggleSourceMute(): void {
        Shell.AudioService.toggleMicrophoneMute()
    }
}
