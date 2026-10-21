import QtQuick
import "../core"

Rectangle {
    id: root

    property bool checked: false
    property bool available: true
    signal toggled(bool checked)

    activeFocusOnTab: available
    // Ink (Config.appearance.ink): Apple switch, 44x26, on = fillOn.
    readonly property bool ink: Config.appearance.ink
    readonly property real knobSize: ink ? 20 : 14
    readonly property real knobInset: 3

    implicitWidth: ink ? 44 : 38
    implicitHeight: ink ? 26 : 20
    radius: height / 2
    opacity: available ? 1 : 0.38
    color: ink ? (checked ? Theme.fillOn : Theme.inkRaised)
        : checked ? Qt.alpha(Theme.primaryContainer, 0.96)
        : Theme.surfaceContainerHigh
    border.width: ink ? 0 : (activeFocus ? 2 : 1)
    border.color: activeFocus ? Theme.primary
        : checked ? Qt.alpha(Theme.primary, 0.72)
        : Qt.alpha(Theme.outlineVariant, 0.64)

    Keys.onSpacePressed: if (available) toggled(!checked)
    Keys.onReturnPressed: if (available) toggled(!checked)
    Keys.onEnterPressed: if (available) toggled(!checked)

    Rectangle {
        width: root.knobSize
        height: root.knobSize
        radius: width / 2
        y: root.ink ? (root.height - height) / 2 : 3
        x: Math.round(knobX.value)
        color: root.ink ? (root.checked ? Theme.glyphOn : Theme.t1)
            : root.checked ? Theme.primary : Theme.surfaceVariantText

        property MotionValue knobX: MotionValue {
            unit: "px"
            omega: Motion.presetSnappy().omega
            zeta: Motion.presetSnappy().zeta
            target: root.checked ? root.width - root.knobSize - root.knobInset
                : root.knobInset
        }
    }

    TapHandler {
        enabled: root.available
        onTapped: {
            root.forceActiveFocus()
            root.toggled(!root.checked)
        }
    }
    Behavior on color { ColorAnimation { duration: Animations.fast } }
}
