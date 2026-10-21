// Desktop adapter over the shell's real services/BrightnessService.qml
// (ddcutil/backlight). Exposes impasto's BrightnessService-shaped API.

pragma Singleton

import QtQuick
import Quickshell
import "../../services" as Shell

Singleton {
    id: root

    readonly property bool available: Shell.BrightnessService.available
    readonly property int percent: Shell.BrightnessService.percentage

    readonly property string icon: {
        if (root.percent < 25)
            return "󰃞"
        if (root.percent < 50)
            return "󰃟"
        if (root.percent < 75)
            return "󰃝"
        return "󰃠"
    }

    function setBrightness(percent: int): void {
        Shell.BrightnessService.setBrightness(percent)
    }
}
