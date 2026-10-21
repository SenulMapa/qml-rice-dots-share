import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"
import "."

// Per-app energy list backed by EnergyService (parity-ledger). `active` must
// be true only while this list is genuinely on screen -- derive it from the
// owner's open/selected state, never from opacity or an ancestor's visible
// (those stay true while faded out). Inactive = ledger watch off, no work.

ColumnLayout {
    id: energy
    visible: EnergyService.available
    spacing: 2

    property bool active: false

    Binding {
        target: EnergyService
        property: "active"
        value: energy.active
    }

    function fmtHours(h: real): string {
        const m = Math.round(h * 60)
        return Math.floor(m / 60) + " h " + (m % 60) + " min"
    }

    readonly property real maxRow: {
        let m = 0
        for (const a of EnergyService.apps)
            if (!a.isPlatform)
                m = Math.max(m, EnergyService.hasWatts ? (a.w || 0) : a.cpuPct)
        return m
    }

    RowLayout {
        Layout.fillWidth: true
        Text {
            text: EnergyService.hasWatts
                ? "Energy · " + EnergyService.totalW.toFixed(1) + " W · " + EnergyService.source
                : "Energy · CPU share"
            color: AdaptiveColor.glassText
            font.family: Config.appearance.fontFamily
            font.pixelSize: Theme.textSmall
            font.weight: Font.DemiBold
        }
        Item { Layout.fillWidth: true }
        Text {
            visible: EnergyService.estHours !== null
            text: EnergyService.estHours !== null
                ? "≈ " + energy.fmtHours(EnergyService.estHours) + " left" : ""
            color: AdaptiveColor.glassTextDim
            font.family: Config.appearance.monoFontFamily
            font.pixelSize: 9
        }
    }

    Repeater {
        model: EnergyService.apps
        delegate: RowLayout {
            required property var modelData
            readonly property bool chipped: modelData.state === "napped"
                || modelData.state === "frozen"
                || modelData.state === "unmanaged"
            Layout.fillWidth: true
            Layout.preferredHeight: 16
            spacing: Theme.space2

            Text {
                Layout.preferredWidth: 110
                text: modelData.name === "screen & platform" ? "Screen & platform" : modelData.name
                elide: Text.ElideRight
                color: AdaptiveColor.glassText
                font.family: Config.appearance.fontFamily
                font.pixelSize: 10
            }
            LevelTrack {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                implicitHeight: 3
                // App bars scale to the biggest app; the platform bar is its share of
                // the whole machine's draw, in a muted colour so it reads as a baseline.
                value: modelData.isPlatform
                    ? (EnergyService.hasWatts && EnergyService.totalW > 0
                        ? Math.min(1, (modelData.w || 0) / EnergyService.totalW) : 0)
                    : (energy.maxRow > 0
                        ? (EnergyService.hasWatts ? (modelData.w || 0) : modelData.cpuPct)
                            / energy.maxRow : 0)
                accent: modelData.isPlatform ? AdaptiveColor.glassTextDim
                    : modelData.state === "focused" ? AdaptiveColor.activeFill
                    : Theme.tertiary
            }
            Rectangle {
                Layout.preferredWidth: 62
                Layout.preferredHeight: 13
                radius: height / 2
                visible: chipped
                color: Qt.alpha(modelData.state === "unmanaged"
                    ? Theme.warning : Theme.success, 0.16)
                Text {
                    anchors.centerIn: parent
                    text: modelData.state
                    color: modelData.state === "unmanaged"
                        ? Theme.warning : Theme.success
                    font.family: Config.appearance.fontFamily
                    font.pixelSize: 8
                }
            }
            Item { visible: !chipped; Layout.preferredWidth: 62 }
            Text {
                Layout.preferredWidth: 44
                horizontalAlignment: Text.AlignRight
                text: modelData.w !== null
                    ? modelData.w.toFixed(1) + " W"
                    : modelData.cpuPct.toFixed(1) + "%"
                color: AdaptiveColor.glassTextDim
                font.family: Config.appearance.monoFontFamily
                font.pixelSize: 9
            }
        }
    }
}
