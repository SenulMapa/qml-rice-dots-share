import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell.Widgets
import "../components"
import "../core"
import "../services"

Item {
    id: root

    function formatPosition(seconds): string {
        if (!Number.isFinite(seconds) || seconds < 0)
            return "0:00"
        const minutes = Math.floor(seconds / 60)
        const remainder = Math.floor(seconds % 60)
        return minutes + ":" + (remainder < 10 ? "0" : "") + remainder
    }

    // Ambient glow: a large, heavily blurred, low-opacity copy of the
    // album art sitting behind the whole page -- ONE soft wash of colour,
    // not a second visible artwork. Absent with no artwork, so an empty
    // player never shows a stale glow.
    Image {
        id: glowSource
        visible: false
        source: MediaService.artwork
        asynchronous: true
        fillMode: Image.PreserveAspectCrop
        width: root.width * 0.7
        height: root.height * 0.7
        anchors.centerIn: parent
    }
    MultiEffect {
        anchors.fill: glowSource
        source: glowSource
        visible: MediaService.available && glowSource.status === Image.Ready
        opacity: 0.32
        blurEnabled: true
        blur: 1.0
        blurMax: 64
        saturation: 0.1
    }

    RowLayout {
        anchors.fill: parent
        visible: MediaService.available
        spacing: Theme.space4

        // Square (1:1), not stretched to the row's full height -- a fixed
        // height here made a near-square source crop into a tall portrait
        // sliver. Centred vertically against the text column next to it.
        ClippingRectangle {
            Layout.preferredWidth: Theme.u(4.4)
            Layout.preferredHeight: Theme.u(4.4)
            Layout.alignment: Qt.AlignVCenter
            radius: Theme.radiusLarge
            color: Theme.surfaceContainerHigh

            Image {
                id: artworkImage
                anchors.fill: parent
                source: MediaService.artwork
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: status === Image.Ready
            }

            Rectangle {
                anchors.fill: parent
                visible: !artworkImage.visible
                color: Qt.alpha(Theme.primaryContainer, Theme.dark ? 0.34 : 0.52)
                Text {
                    anchors.centerIn: parent
                    text: "󰝚"
                    color: AdaptiveColor.activeFill
                    font.family: Config.appearance.monoFontFamily
                    font.pixelSize: 56
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.space3

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: MediaService.identity
                    color: AdaptiveColor.glassTextDim
                    elide: Text.ElideRight
                    font.family: Config.appearance.monoFontFamily
                    font.pixelSize: 9
                    font.letterSpacing: 0.6
                }
                Text {
                    visible: MediaService.playerCount > 1
                    text: "󰒭  Next player"
                    color: playerHover.hovered ? AdaptiveColor.activeFill
                        : AdaptiveColor.glassTextDim
                    font.family: Config.appearance.fontFamily
                    font.pixelSize: 9
                    HoverHandler { id: playerHover }
                    TapHandler { onTapped: MediaService.selectNextPlayer() }
                }
            }

            // The title IS the page's expressive centrepiece now -- one
            // big line, display font, none of the small-caps chrome the
            // "Spotify" strip used to carry.
            Text {
                Layout.fillWidth: true
                text: MediaService.title
                color: AdaptiveColor.glassText
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.Wrap
                font.family: Config.appearance.displayFontFamily
                font.pixelSize: Theme.textTitle + 14
                font.weight: Font.Normal
            }
            Text {
                Layout.fillWidth: true
                text: MediaService.artist
                color: AdaptiveColor.glassTextDim
                elide: Text.ElideRight
                font.family: Config.appearance.fontFamily
                font.pixelSize: 13
                font.weight: Font.Medium
            }
            Text {
                Layout.fillWidth: true
                visible: text.length > 0
                text: MediaService.album
                color: Qt.alpha(AdaptiveColor.glassTextDim, 0.72)
                elide: Text.ElideRight
                font.family: Config.appearance.fontFamily
                font.pixelSize: 10
            }

            Item { Layout.preferredHeight: Theme.space2 }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 12

                WaveTrack {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    value: MediaService.progress
                    playing: MediaService.playing
                    accent: AdaptiveColor.activeFill
                }
                TapHandler {
                    enabled: MediaService.canSeek
                    onTapped: eventPoint => MediaService.seekTo(
                        eventPoint.position.x / parent.width)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: root.formatPosition(MediaService.position)
                    color: AdaptiveColor.glassTextDim
                    font.family: Config.appearance.monoFontFamily
                    font.pixelSize: 8
                }
                Text {
                    text: root.formatPosition(MediaService.duration)
                    color: AdaptiveColor.glassTextDim
                    font.family: Config.appearance.monoFontFamily
                    font.pixelSize: 8
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Theme.space4

                Repeater {
                    // A fixed 3-entry model -- NOT an array literal keyed
                    // on MediaService's own live properties. That used to
                    // be a plain array of {icon, action, available}
                    // objects recomputed from MediaService.playing/can*;
                    // Repeater treats a fresh array as a full model reset,
                    // silently destroying and recreating all three
                    // delegates every time playback state changed. Nothing
                    // noticed while the delegate was a plain Rectangle, but
                    // it destroys the buttons' own press/morph springs
                    // mid-flight now -- each delegate below reads
                    // MediaService directly instead.
                    model: ["previous", "toggle", "next"]
                    delegate: Rectangle {
                        id: transportBtn
                        required property string modelData
                        readonly property string action: modelData
                        readonly property bool primary: action === "toggle"
                        readonly property bool available: action === "previous"
                            ? MediaService.canPrevious
                            : action === "next" ? MediaService.canNext
                            : MediaService.canToggle
                        readonly property string icon: action === "previous" ? "󰒮"
                            : action === "next" ? "󰒭"
                            : (MediaService.playing ? "󰏤" : "󰐊")
                        Layout.preferredWidth: primary ? 52 : 40
                        Layout.preferredHeight: primary ? 52 : 40
                        // The primary button morphs circle <-> rounded
                        // square with playback state instead of just
                        // swapping its glyph -- paused reads as a full
                        // circle (play, ready to roll), playing settles
                        // into a squircle (pause, "something is happening").
                        radius: primary
                            ? (MediaService.playing ? radiusSpring.value : width / 2)
                            : width / 2

                        MotionValue {
                            id: radiusSpring
                            unit: "px"
                            omega: Motion.omegaEnter
                            zeta: Motion.zetaEnter
                            target: transportBtn.width * 0.32
                        }

                        opacity: available ? 1 : 0.36
                        color: primary ? AdaptiveColor.activeFill
                            : mediaHover.hovered ? Theme.surfaceContainerHigh
                            : Qt.alpha(Theme.surfaceContainerHigh, 0.64)

                        scale: pressScale.value
                        MotionValue {
                            id: pressScale
                            unit: "ratio"
                            omega: Motion.omegaEnter
                            zeta: 0.55
                            target: mediaTap.pressed ? 0.92 : 1
                        }

                        Text {
                            anchors.centerIn: parent
                            text: transportBtn.icon
                            color: transportBtn.primary ? AdaptiveColor.activeFillText : AdaptiveColor.glassText
                            font.family: Config.appearance.monoFontFamily
                            font.pixelSize: transportBtn.primary ? 22 : 17
                        }
                        HoverHandler { id: mediaHover; enabled: transportBtn.available }
                        TapHandler {
                            id: mediaTap
                            enabled: transportBtn.available
                            onTapped: {
                                if (transportBtn.action === "previous") MediaService.previous()
                                else if (transportBtn.action === "next") MediaService.next()
                                else MediaService.togglePlaying()
                            }
                        }
                        Behavior on color {
                            ColorAnimation { duration: Animations.fast }
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        visible: !MediaService.available
        spacing: Theme.space3

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "󰝚"
            color: AdaptiveColor.activeFill
            font.family: Config.appearance.monoFontFamily
            font.pixelSize: 48
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "Nothing playing"
            color: AdaptiveColor.glassText
            font.family: Config.appearance.displayFontFamily
            font.pixelSize: Theme.textTitle + 6
            font.weight: Font.Normal
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "Media controls will appear when an MPRIS player is active."
            color: AdaptiveColor.glassTextDim
            font.family: Config.appearance.fontFamily
            font.pixelSize: 10
        }
    }
}
