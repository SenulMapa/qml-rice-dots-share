// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   T O G G L E   S W I T C H                                              │
// │   an on/off control for a settings row                                   │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯
//
// Adaptation: Theme -> DeskTheme.

import QtQuick
import "../services" as DeskServices

// The knob slides rather than jumping, so the switch shows which way it
// went. Disabled, it fades instead of turning grey.
Rectangle {
    id: root

    property bool checked: false

    signal toggled(bool checked)

    implicitWidth: 40
    implicitHeight: 22
    radius: height / 2
    opacity: root.enabled ? 1 : 0.45

    Behavior on opacity { NumberAnimation { duration: DeskServices.DeskTheme.durationFast } }

    color: root.checked ? DeskServices.DeskTheme.accent : DeskServices.DeskTheme.islandSurfaceHover
    border.color: root.checked ? DeskServices.DeskTheme.accent : DeskServices.DeskTheme.islandBorder
    border.width: 1

    Behavior on color { ColorAnimation { duration: DeskServices.DeskTheme.durationFast } }
    Behavior on border.color { ColorAnimation { duration: DeskServices.DeskTheme.durationFast } }

    Rectangle {
        y: 3
        x: root.checked ? root.width - width - 3 : 3
        width: root.height - 6
        height: width
        radius: width / 2
        color: root.checked ? DeskServices.DeskTheme.accentText : DeskServices.DeskTheme.textMuted

        Behavior on x {
            NumberAnimation { duration: DeskServices.DeskTheme.durationFast; easing.type: DeskServices.DeskTheme.easing }
        }
        Behavior on color { ColorAnimation { duration: DeskServices.DeskTheme.durationFast } }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.enabled
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.toggled(!root.checked)
    }
}
