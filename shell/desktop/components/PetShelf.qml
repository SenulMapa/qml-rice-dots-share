// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   P E T   S H E L F                                                      │
// │   pet shelf · one slot per species                                       │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯
//
// Adaptation: Theme -> DeskTheme, PetService -> DeskPetService.

import QtQuick
import QtQuick.Layouts
import "../services" as DeskServices

// The collection in one row: a slot per species (sleeping pets shown,
// undiscovered ones empty) and a line saying what earns the next. Clicking a
// sleeping pet brings it out. Used in the module detail and the control
// centre block.
RowLayout {
    id: root

    // Slot size, and whether to use the short caption (for the narrower
    // control centre block).
    property int slot: 32
    property bool brief: false

    spacing: 6

    Repeater {
        model: DeskServices.DeskPetService.species.length

        Rectangle {
            id: slot

            required property int index

            readonly property bool filled: slot.index < DeskServices.DeskPetService.family.length
            readonly property bool out: slot.index === DeskServices.DeskPetService.activeIndex

            implicitWidth: root.slot
            implicitHeight: root.slot
            radius: width / 2
            color: slot.out
                ? DeskServices.DeskTheme.islandSurface
                : (slotMouse.containsMouse ? DeskServices.DeskTheme.islandSurfaceHover : "transparent")
            border.width: 1
            // The active pet in white; sleepers outlined, empty slots faint.
            border.color: slot.out
                ? DeskServices.DeskTheme.indicator
                : (slot.filled ? DeskServices.DeskTheme.islandBorder : DeskServices.DeskTheme.hairline)

            Behavior on color { ColorAnimation { duration: DeskServices.DeskTheme.durationFast } }

            PetFace {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -1
                visible: slot.filled
                size: Math.round(root.slot * 0.625)
                record: DeskServices.DeskPetService.recordAt(slot.index)
                mood: DeskServices.DeskPetService.moodAt(slot.index)
            }

            MouseArea {
                id: slotMouse

                anchors.fill: parent
                hoverEnabled: slot.filled && !slot.out
                cursorShape: slot.filled && !slot.out
                    ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: DeskServices.DeskPetService.bringOut(slot.index)
            }
        }
    }

    Text {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignRight
        text: {
            if (DeskServices.DeskPetService.complete)
                return "All five found"
            const left = DeskServices.DeskPetService.levelsToNextEgg
            if (root.brief)
                return `${left} to the next egg`
            return left === 1
                ? "1 level to the next egg"
                : `${left} levels to the next egg`
        }
        elide: Text.ElideRight
        font.family: DeskServices.DeskTheme.fontFamily
        font.pixelSize: DeskServices.DeskTheme.fontSizeLabel
        color: DeskServices.DeskTheme.textMuted
    }
}
