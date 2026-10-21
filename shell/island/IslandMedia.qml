import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import "../components"
import "../core"
import "../services"

Item {
    id: root

    function fmt(sec: real): string {
        const t = Math.max(0, Math.floor(sec))
        return Math.floor(t / 60) + ":" + String(t % 60).padStart(2, "0")
    }

    // The original compact layout, kept whole for ink-off.
    RowLayout {
        visible: !Config.appearance.ink
        anchors.fill: parent
        anchors.leftMargin: Theme.space5
        anchors.rightMargin: Theme.space5
        anchors.topMargin: Theme.space2
        anchors.bottomMargin: Theme.space2
        spacing: Theme.space3

        ClippingRectangle {
            Layout.preferredWidth: 68
            Layout.preferredHeight: 68
            // Circular per the owner's Figma redesign (node 4:20).
            radius: width / 2
            color: Theme.surfaceContainerHigh

            Image {
                id: islandArtwork
                anchors.fill: parent
                source: MediaService.artwork
                visible: status === Image.Ready
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
            }

            Text {
                anchors.centerIn: parent
                visible: !islandArtwork.visible
                text: "󰝚"
                color: AdaptiveColor.activeFill
                font.family: Config.appearance.monoFontFamily
                // DisplayScale.primary: bare literal alongside otherwise
                // Theme-token-driven sizing in this file.
                font.pixelSize: Math.round(22 * DisplayScale.primary)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.space1

            Text {
                Layout.fillWidth: true
                text: MediaService.title
                color: AdaptiveColor.glassText
                elide: Text.ElideRight
                maximumLineCount: 1
                font.family: Config.appearance.fontFamily
                font.pixelSize: Theme.textBody
                font.weight: Font.DemiBold
            }

            Text {
                Layout.fillWidth: true
                text: MediaService.artist
                color: AdaptiveColor.glassTextDim
                elide: Text.ElideRight
                maximumLineCount: 1
                font.family: Config.appearance.fontFamily
                font.pixelSize: Theme.textSmall
            }

            WaveTrack {
                Layout.fillWidth: true
                Layout.topMargin: Theme.space1
                value: MediaService.progress
                playing: MediaService.playing
                // Was Theme.tertiary (purple) -- the owner's Figma (node
                // 4:20) draws this progress bar in --primary (teal).
                accent: AdaptiveColor.activeFill
            }
        }

        // Small vertical level meter at the popup's trailing edge -- see
        // the owner's Figma redesign (node 4:20). Same absent-when-idle
        // rule as every other Eq use in this shell (island/Eq.qml).
        Eq {
            Layout.alignment: Qt.AlignVCenter
            active: MediaService.playing
            visible: MediaService.playing
            maxH: 16
            barColor: AdaptiveColor.activeFill
        }
    }

    // Ink shared-element tags (island/SharedElements.qml): the media face's
    // art and title/artist slots. Only the active "media" state counts.
    SharePoint {
        id: shareArt
        objectName: "share:art"
        shareKind: "art"
        shareState: "media"
        measure: mediaArt
        shareRadius: 22
    }
    SharePoint {
        id: shareTitle
        objectName: "share:title"
        shareKind: "title"
        shareState: "media"
        measure: mediaTitleCol
    }
    readonly property var shareItems: [shareArt, shareTitle]

    // Ink (Config.appearance.ink): the 560x232 media face from
    // showcase/screens/island-states.html -- 168px art, title and artist,
    // the owner's WaveTrack, a serif elapsed time, and a transport row with
    // a fillOn play disc. The art glow halo is not drawn here (it needs the
    // blob surface layer, outside this file).
    Item {
        visible: Config.appearance.ink
        anchors.fill: parent
        anchors.margins: 32

        RowLayout {
            anchors.fill: parent
            spacing: 28

            // Placeholder only: SharedArt (island/SharedElements.qml) draws
            // the art at exactly this 168px slot, which is also what keeps
            // the title column (and the serif elapsed time) to its right.
            Item {
                id: mediaArt
                Layout.preferredWidth: 168
                Layout.minimumWidth: 168
                Layout.maximumWidth: 168
                Layout.preferredHeight: 168
                Layout.minimumHeight: 168
                Layout.maximumHeight: 168
                Layout.alignment: Qt.AlignVCenter
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                ColumnLayout {
                    id: mediaTitleCol
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        Layout.fillWidth: true
                        // SharedTitle draws it under ink.
                        opacity: 0
                        text: MediaService.title
                        color: Theme.t1
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        font.family: Theme.fontUi
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                        font.letterSpacing: -0.3
                    }

                    Text {
                        Layout.fillWidth: true
                        opacity: 0
                        text: MediaService.artist
                        color: Theme.t2
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        font.family: Theme.fontUi
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }
                }

                Item { Layout.fillHeight: true }

                WaveTrack {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 24
                    value: MediaService.progress
                    playing: MediaService.playing
                    accent: Theme.fillOn
                }

                Item { Layout.fillHeight: true }

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        Layout.alignment: Qt.AlignBaseline
                        text: root.fmt(MediaService.position)
                        color: Theme.t1
                        font.family: Theme.fontSerif
                        font.pixelSize: 44
                        font.letterSpacing: -0.9
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        Layout.alignment: Qt.AlignBaseline
                        text: "-" + root.fmt(Math.max(0, MediaService.duration - MediaService.position))
                        color: Theme.t3
                        font.family: Theme.fontUi
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }
                }

                Item { Layout.fillHeight: true }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14

                    Icon {
                        name: "transport/prev"
                        size: 28
                        color: Theme.t1
                        opacity: MediaService.canPrevious ? 1 : 0.4
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            enabled: MediaService.canPrevious
                            onClicked: MediaService.previous()
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 44
                        Layout.preferredHeight: 44
                        radius: 22
                        color: Theme.fillOn

                        Icon {
                            anchors.centerIn: parent
                            anchors.horizontalCenterOffset: MediaService.playing ? 0 : 1
                            name: MediaService.playing ? "transport/pause" : "transport/play"
                            size: 20
                            color: Theme.glyphOn
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: MediaService.canToggle
                            onClicked: MediaService.togglePlaying()
                        }
                    }

                    Icon {
                        name: "transport/next"
                        size: 28
                        color: Theme.t1
                        opacity: MediaService.canNext ? 1 : 0.4
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            enabled: MediaService.canNext
                            onClicked: MediaService.next()
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: MediaService.identity
                        color: Theme.t3
                        elide: Text.ElideRight
                        Layout.maximumWidth: 120
                        font.family: Theme.fontUi
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }
                }
            }
        }
    }
}
