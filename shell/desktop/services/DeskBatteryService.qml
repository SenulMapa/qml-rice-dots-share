// Desktop adapter over the shell's real services/BatteryService.qml (UPower).
// Exposes impasto's BatteryService-shaped API (percent/estimate/stateWord/
// low/tint/watts) so faces/analogue/BatteryFace.qml and faces/Squares.qml's
// battery face can bind without any per-property TODOs.

pragma Singleton

import QtQuick
import Quickshell
import "../../services" as Shell
import "." as DeskServices

Singleton {
    id: root

    readonly property bool available: Shell.BatteryService.available
    readonly property int percent: Shell.BatteryService.percentageInt
    readonly property bool charging: Shell.BatteryService.charging
    readonly property bool full: Shell.BatteryService.fullyCharged
    readonly property bool onBattery: Shell.BatteryService.onBattery
    readonly property real energy: Shell.BatteryService.energy
    readonly property real watts: Shell.BatteryService.chargeRate
    readonly property string icon: Shell.BatteryService.icon

    // impasto's "estimate": time-to-full while charging, time-to-empty on
    // battery, "" otherwise -- the shell's own charge/emptyTimeLabel already
    // do exactly this.
    readonly property string estimate: root.charging
        ? Shell.BatteryService.chargeTimeLabel
        : (root.onBattery ? Shell.BatteryService.emptyTimeLabel : "")

    readonly property string stateWord: !root.available ? "No battery"
        : root.full ? "Fully charged"
        : root.charging ? "Charging"
        : root.onBattery ? "On battery" : "Plugged in"

    // Fixed battery-red below 20%, matching impasto's BatteryFace comment
    // ("the fill takes the fixed battery red when the charge is low").
    readonly property bool low: root.available && !root.charging && !root.full
        && root.percent <= 20
    readonly property color tint: DeskServices.DeskTheme.red

    // impasto's BatteryModule detail card (island/cards/BatteryCard.qml):
    // cells that don't report health get the raw energy capacity instead of
    // a guess -- see services/BatteryService.qml's own healthAvailable/
    // healthPercentageInt/energyCapacity, read directly here rather than
    // re-derived.
    readonly property bool healthKnown: Shell.BatteryService.healthAvailable
    readonly property int health: Shell.BatteryService.healthPercentageInt
    readonly property real energyCapacity: Shell.BatteryService.energyCapacity
}
