// DEPRECATED: Old widget system. Use desktop/ instead
import QtQuick
import "../core"
import "../services"
import "../components"

/**
 * MediaWidget -- art in a rounded shape + title/artist. Only ever
 * instantiated while something is playing (see WidgetHost.qml's
 * Loader.active gate), so it costs nothing the rest of the time. No
 * transport controls in v1 -- the island already owns those; this is an
 * at-a-glance surface only.
 */
Item {
    id: root

    Squircle {
        anchors.fill: parent
        radius: Theme.radiusFor(height)
        color: Theme.surfaceContainerHigh
    }

    Row {
        anchors.fill: parent
        anchors.margins: Theme.space3
        spacing: Theme.space3

        Rectangle {
            id: artFrame
            width: height
            height: parent.height
            radius: Theme.radiusMedium
            color: Theme.primaryContainer
            clip: true

            Image {
                anchors.fill: parent
                source: MediaService.artwork
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                sourceSize.width: artFrame.width
                sourceSize.height: artFrame.height
                visible: status === Image.Ready
            }
        }

        Column {
            width: parent.width - artFrame.width - Theme.space3
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.space1

            Text {
                width: parent.width
                text: MediaService.title
                elide: Text.ElideRight
                font.family: Config.appearance.fontFamily
                font.pixelSize: Theme.textBody
                font.weight: Font.DemiBold
                color: Theme.surfaceText
            }
            Text {
                width: parent.width
                text: MediaService.artist
                elide: Text.ElideRight
                font.family: Config.appearance.fontFamily
                font.pixelSize: Theme.textSmall
                color: Theme.surfaceVariantText
            }
        }
    }
}
