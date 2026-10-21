// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   S L I D E R   R O W                                                    │
// │   a level control · icon, track and reading                              │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../services" as DeskServices


// The track is the control: it is dragged directly, and the icon sitting
// inside it is the target for muting rather than a separate button.
Item {
    id: root

    property string icon: ""
    property int value: 0
    property int from: 0
    property int to: 100
    property bool available: true
    property bool dimmed: false

    signal moved(int value)
    signal iconClicked()

    implicitHeight: 40

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: DeskServices.DeskTheme.islandSurface
        border.color: slider.hovered ? DeskServices.DeskTheme.islandBorder : "transparent"
        border.width: 1
        opacity: root.available ? 1 : 0.45

        Behavior on border.color { ColorAnimation { duration: DeskServices.DeskTheme.durationFast } }

        // Fill behind everything: the whole row is the track.
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Math.max(parent.height, parent.width * slider.position)
            radius: parent.radius
            color: root.dimmed ? DeskServices.DeskTheme.islandSurfaceHover : DeskServices.DeskTheme.accent
            opacity: root.dimmed ? 1 : 0.9

            Behavior on width {
                NumberAnimation { duration: DeskServices.DeskTheme.durationFast; easing.type: DeskServices.DeskTheme.easing }
            }
            Behavior on color { ColorAnimation { duration: DeskServices.DeskTheme.durationFast } }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 13
            anchors.rightMargin: 14
            spacing: 10

            Text {
                text: root.icon
                font.family: DeskServices.DeskTheme.fontMono
                font.pixelSize: 15
                color: root.dimmed ? DeskServices.DeskTheme.textMuted : DeskServices.DeskTheme.accentText

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.iconClicked()
                }
            }

            Item { Layout.fillWidth: true }

            // DeskServices.DeskTheme.text rather than accentText: the fill only reaches the
            // reading at 100%.
            Text {
                text: `${root.value}%`
                font.family: DeskServices.DeskTheme.fontFamily
                font.pixelSize: DeskServices.DeskTheme.fontSizeSmall
                font.weight: Font.DemiBold
                color: root.dimmed ? DeskServices.DeskTheme.textMuted : DeskServices.DeskTheme.text
            }
        }

        // Invisible; supplies only the drag behaviour.
        Slider {
            id: slider
            anchors.fill: parent
            from: root.from
            to: root.to
            value: root.value
            enabled: root.available
            opacity: 0
            onMoved: root.moved(Math.round(slider.value))
        }
    }
}
