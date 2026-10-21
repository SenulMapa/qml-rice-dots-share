// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   U S A G E   B A R                                                      │
// │   a track and how much of it has gone                                    │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick
import "../services" as DeskServices


// A thin horizontal gauge: a fraction and a colour. The fill keeps rounded
// ends even when empty.
Rectangle {
    id: root

    property real progress: 0
    property color fillColor: DeskServices.DeskTheme.accent
    property color trackColor: DeskServices.DeskTheme.islandSurfaceHover

    readonly property real clamped: Math.max(0, Math.min(1, root.progress))

    implicitWidth: 120
    implicitHeight: 6
    radius: height / 2
    color: root.trackColor

    Rectangle {
        height: parent.height
        // Never narrower than it is tall, so the end stays round.
        width: root.clamped <= 0 ? 0 : Math.max(parent.height, parent.width * root.clamped)
        radius: height / 2
        color: root.fillColor

        Behavior on width {
            NumberAnimation { duration: DeskServices.DeskTheme.durationMedium; easing.type: DeskServices.DeskTheme.easing }
        }
        Behavior on color { ColorAnimation { duration: DeskServices.DeskTheme.durationMedium } }
    }
}
