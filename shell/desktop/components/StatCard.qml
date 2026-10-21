// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   S T A T   C A R D                                                      │
// │   a figure, its history and whatever detail belongs under it             │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯
//
// Adaptation: Theme -> DeskTheme; `Card` from ../../dashboard/components
// (already ported there from impasto's own components/Card.qml).

import QtQuick
import QtQuick.Layouts
import "../services" as DeskServices
import "../../dashboard/components" as DashComponents

// The sparkline sits behind the reading as the card's background.
DashComponents.Card {
    id: root

    property string icon: ""
    property string title: ""
    property string reading: ""
    property string detail: ""
    property var series: []
    property real maximum: 1
    property color accent: DeskServices.DeskTheme.accent

    default property alias extra: extraHolder.data

    padding: 0

    // Stops above the extra row, so it never overlaps the per-core bars.
    Sparkline {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 1
        anchors.rightMargin: 1
        anchors.bottom: parent.bottom
        anchors.bottomMargin: extraHolder.implicitHeight > 0
            ? extraHolder.implicitHeight + 20 : 1
        height: Math.max(28, parent.height * 0.58 - extraHolder.implicitHeight)
        values: root.series
        maximum: root.maximum
        stroke: root.accent
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 9

            Text {
                text: root.icon
                font.family: DeskServices.DeskTheme.fontMono
                font.pixelSize: 15
                color: root.accent
            }

            Text {
                text: root.title
                font.family: DeskServices.DeskTheme.fontFamily
                font.pixelSize: DeskServices.DeskTheme.fontSizeSmall
                font.weight: Font.DemiBold
                color: DeskServices.DeskTheme.text
            }

            Item { Layout.fillWidth: true }

            Text {
                text: root.reading
                font.family: DeskServices.DeskTheme.fontFamily
                font.pixelSize: DeskServices.DeskTheme.fontSizeLarge
                font.weight: Font.DemiBold
                color: DeskServices.DeskTheme.text
            }
        }

        Text {
            Layout.fillWidth: true
            text: root.detail
            elide: Text.ElideRight
            font.family: DeskServices.DeskTheme.fontFamily
            font.pixelSize: DeskServices.DeskTheme.fontSizeLabel
            color: DeskServices.DeskTheme.textMuted
        }

        Item { Layout.fillHeight: true }

        // A ColumnLayout, not an Item: children need a width, and a bare
        // Item's childrenRect gives them none.
        ColumnLayout {
            id: extraHolder
            Layout.fillWidth: true
            spacing: 6
        }
    }
}
