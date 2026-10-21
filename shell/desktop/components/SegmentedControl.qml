// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   S E G M E N T E D   C O N T R O L                                      │
// │   pick one of a few, with all of them visible                            │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick
import QtQuick.Layouts
import "../services" as DeskServices
import "../../components"

// For two or three options, all visible at once.
Squircle {
    id: root

    // Entries of { id, label }, or { id, label, icon }: an entry with an icon
    // shows only the glyph, and its label appears above the control on hover.
    property var options: []
    property string current: ""
    property int iconSize: DeskServices.DeskTheme.fontSizeLarge
    // Distance from the control's top edge to the hovered label.
    property int tipGap: 6

    signal selected(string id)

    // The segment under the pointer.
    property Item hovered: null

    implicitWidth: layout.implicitWidth + 6
    implicitHeight: 28
    radius: DeskServices.DeskTheme.radiusSmall
    opacity: root.enabled ? 1 : 0.45

    Behavior on opacity { NumberAnimation { duration: DeskServices.DeskTheme.durationFast } }
    color: DeskServices.DeskTheme.islandSurfaceHover
    borderColor: DeskServices.DeskTheme.islandBorder
    borderWidth: 1

    RowLayout {
        id: layout
        anchors.centerIn: parent
        spacing: 2

        Repeater {
            model: root.options

            Squircle {
                id: segment

                required property var modelData
                readonly property bool active: segment.modelData.id === root.current
                readonly property bool glyph: (segment.modelData.icon ?? "") !== ""

                Layout.preferredHeight: root.implicitHeight - 6
                Layout.preferredWidth: segment.glyph
                    ? Layout.preferredHeight
                    : Math.max(64, label.implicitWidth + 20)
                radius: DeskServices.DeskTheme.radiusSmall - 2
                color: segment.active ? DeskServices.DeskTheme.accent
                    : (segmentMouse.containsMouse ? DeskServices.DeskTheme.islandBorder : "transparent")

                Behavior on color { ColorAnimation { duration: DeskServices.DeskTheme.durationFast } }

                Text {
                    id: label
                    anchors.centerIn: parent
                    text: segment.glyph ? segment.modelData.icon : segment.modelData.label
                    font.family: segment.glyph ? DeskServices.DeskTheme.fontMono : DeskServices.DeskTheme.fontFamily
                    font.pixelSize: segment.glyph ? root.iconSize : DeskServices.DeskTheme.fontSizeSmall
                    font.weight: segment.active ? Font.DemiBold : Font.Normal
                    color: segment.active ? DeskServices.DeskTheme.accentText
                        : (segment.glyph && segmentMouse.containsMouse ? DeskServices.DeskTheme.text
                                                                        : DeskServices.DeskTheme.textMuted)
                }

                MouseArea {
                    id: segmentMouse
                    anchors.fill: parent
                    enabled: root.enabled
                    hoverEnabled: true
                    cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.selected(segment.modelData.id)
                    onContainsMouseChanged: {
                        if (containsMouse)
                            root.hovered = segment
                        else if (root.hovered === segment)
                            root.hovered = null
                    }
                }
            }
        }
    }

    // ── LABEL ───────────────────────────────────────────────────────────────
    //
    // The hovered glyph's name, centred over it. It keeps the last segment
    // through the fade-out, so the name does not blank before it is gone.

    Rectangle {
        id: tip

        property Item target: null

        Binding on target {
            when: root.hovered !== null && root.hovered.glyph
            value: root.hovered
            restoreMode: Binding.RestoreNone
        }

        visible: opacity > 0
        opacity: root.hovered !== null && root.hovered.glyph ? 1 : 0
        x: tip.target === null ? 0
            : layout.x + tip.target.x + (tip.target.width - tip.width) / 2
        y: -tip.height - root.tipGap
        width: tipText.implicitWidth + 20
        height: 26
        radius: height / 2
        color: DeskServices.DeskTheme.island
        border.color: DeskServices.DeskTheme.islandBorder
        border.width: 1

        Behavior on opacity { NumberAnimation { duration: DeskServices.DeskTheme.durationFast } }
        Behavior on x {
            enabled: tip.opacity > 0
            NumberAnimation { duration: DeskServices.DeskTheme.durationFast; easing.type: DeskServices.DeskTheme.easing }
        }

        Text {
            id: tipText
            anchors.centerIn: parent
            text: tip.target === null ? "" : tip.target.modelData.label
            font.family: DeskServices.DeskTheme.fontFamily
            font.pixelSize: DeskServices.DeskTheme.fontSizeSmall
            font.weight: Font.DemiBold
            color: DeskServices.DeskTheme.text
        }
    }
}
