import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import "../core"
import "../components"

/**
 * MacWidgetNowPlaying -- the Now Playing widget (spec 3.3, owner spec 21 Oct),
 * shown only while MediaService has a player. A compact row: artwork on the
 * left, title and artist stacked beside it, transport controls on the right.
 * Reads MediaService (or a stand-in with its members).
 */
Item {
    id: root

    required property var media

    width: MacTokens.s(MacTokens.ncColumnWidth)
    height: MacTokens.s(MacTokens.ncMediaHeight)

    readonly property real pad: MacTokens.s(MacTokens.ncMediaPad)
    readonly property real gap: MacTokens.s(MacTokens.ncMediaGap)

    TahoeSurface {
        anchors.fill: parent
        kind: "nc"
        radius: MacTokens.s(MacTokens.ncWidgetRadius)
        tintAlpha: MacTokens.frostTintAlpha
        fill: MacTokens.ncWidgetFrost
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: root.gap

        ClippingRectangle {
            id: art
            Layout.preferredWidth: MacTokens.s(MacTokens.ncArtSize)
            Layout.preferredHeight: MacTokens.s(MacTokens.ncArtSize)
            Layout.alignment: Qt.AlignVCenter
            radius: MacTokens.s(MacTokens.ncArtRadius)
            // Neutral until the artwork loads; a flat accent square read as a broken tile.
            color: MacTokens.onSurface(0.08)

            Image {
                id: artImage
                anchors.fill: parent
                source: root.media.artwork
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: status === Image.Ready
            }

            Icon {
                anchors.centerIn: parent
                visible: artImage.status !== Image.Ready
                name: "music"
                size: MacTokens.s(MacTokens.ncMediaGlyphSize) + 6
                color: MacTokens.labelSecondary
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 0

            Text {
                Layout.fillWidth: true
                text: root.media.title
                color: MacTokens.labelPrimary
                elide: Text.ElideRight
                maximumLineCount: 1
                font.family: MacTokens.textFamily
                font.pixelSize: MacTokens.s(MacTokens.ncWidgetTitleSize)
                font.weight: Font.DemiBold
            }

            Text {
                Layout.fillWidth: true
                text: root.media.artist
                color: MacTokens.labelSecondary
                elide: Text.ElideRight
                maximumLineCount: 1
                font.family: MacTokens.textFamily
                font.pixelSize: MacTokens.s(MacTokens.ncMediaArtistSize)
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignVCenter
            spacing: 0

            Repeater {
                model: [
                    { glyph: "󰒮", run: "previous" },
                    { glyph: root.media.playing ? "󰏤" : "󰐊", run: "togglePlaying" },
                    { glyph: "󰒭", run: "next" }
                ]

                delegate: Text {
                    required property var modelData
                    Layout.preferredWidth: MacTokens.s(MacTokens.ncMediaButtonSize)
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData.glyph
                    color: MacTokens.labelPrimary
                    font.family: MacTokens.displayFamily
                    font.pixelSize: MacTokens.s(MacTokens.ncMediaGlyphSize)

                    TapHandler {
                        onTapped: {
                            if (modelData.run === "previous")
                                root.media.previous()
                            else if (modelData.run === "next")
                                root.media.next()
                            else
                                root.media.togglePlaying()
                        }
                    }
                }
            }
        }
    }
}
