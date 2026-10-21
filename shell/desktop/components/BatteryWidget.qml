// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   B A T T E R Y   W I D G E T                                            │
// │   charge as a ring · the level is the outline                            │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick
import "../services" as DeskServices


// The outline is the charge level; the exact figure is in the island detail.
// No background of its own: whatever hosts the ring supplies it.
RingIndicator {
    id: root

    // Smaller inside the island, where the capsule's edge would clip it.
    property real size: DeskServices.DeskTheme.capsuleHeight

    // A desktop face passes its own ink so the ring reads on its background.
    property color glyphColor: DeskServices.DeskTheme.indicator
    property color track: DeskServices.DeskTheme.indicatorDim

    implicitWidth: root.size
    implicitHeight: root.size

    visible: DeskServices.DeskBatteryService.available
    progress: DeskServices.DeskBatteryService.percent / 100
    thickness: 2.5

    trackColor: root.track
    fillColor: DeskServices.DeskBatteryService.tint

    Behavior on fillColor { ColorAnimation { duration: DeskServices.DeskTheme.durationMedium } }

    Text {
        anchors.centerIn: parent
        text: DeskServices.DeskBatteryService.icon
        font.family: DeskServices.DeskTheme.fontMono
        font.pixelSize: Math.round(root.size * 0.38)
        // The ring carries the level; the glyph only says what is measured.
        color: root.glyphColor
    }
}
