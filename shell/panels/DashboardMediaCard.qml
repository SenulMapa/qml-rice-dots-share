import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import "../components"
import "../core"
import "../services"

DashboardCard {
    id: root

    signal pageRequested()

    accent: AdaptiveColor.activeFill
    onActivated: root.pageRequested()

    RowLayout {
        anchors.fill: parent
        // Figma (node 9:3): 14px margins on every edge, 14px gap between
        // the art and the meta column.
        anchors.margins: Theme.u(14 / 44)
        spacing: Theme.u(14 / 44)

        // Album art -- a perfect circle (like island/IslandMedia.qml's own
        // ClippingRectangle), no longer the Figma blob mask. Sized
        // proportionally to the card's own width instead of a fixed 112px,
        // same as before, so it tracks the card at any size.
        Item {
            id: artSlot
            Layout.preferredWidth: root.width * (203.7 / 517)
            Layout.fillHeight: true

            // Card is genuinely on screen: island/Island.qml hides the whole
            // expanded surface (which the Dashboard, and this card, live
            // inside) via opacity/enabled on its wrapper Item, NOT visible,
            // when the island is dormant/hovering instead of expanded --
            // same reasoning the old blob wobble clock's header documented.
            // Both are needed here to gate the ring's rotation and the cava
            // spectrum process so neither runs against a collapsed island.
            readonly property bool cardOnScreen: root.visible && root.enabled
            readonly property bool artReady: MediaService.available
                && dashboardArtwork.status === Image.Ready
            readonly property bool ringSpinning: artSlot.cardOnScreen
                && MediaService.playing

            // Ring geometry, all derived from the slot's own limiting
            // dimension so the ring (art + gap + bars) never exceeds the
            // slot's box -- no clipping needed, no overlap with the meta
            // column next door. The art diameter is a pure function of
            // ringOuter/ringMargin with no dependency on playing/available,
            // so it can never visibly jump size between idle and playing --
            // only the ring's own opacity/scale (below) changes with state.
            readonly property real ringOuter: Math.min(width, height)
            readonly property real ringGap: Theme.u(0.05)
            readonly property real barMinLen: Theme.u(0.06)
            readonly property real barMaxLen: Theme.u(0.4)
            readonly property real barWidth: Theme.u(0.08)
            readonly property real ringMargin: artSlot.ringGap + artSlot.barMaxLen
            readonly property real circleDiameter: Math.max(
                0, artSlot.ringOuter - 2 * artSlot.ringMargin)

            Component.onCompleted: {
                VisualizerService.setSpectrumVisible(
                    "dashboard-media-card", artSlot.cardOnScreen)
            }
            onCardOnScreenChanged: VisualizerService.setSpectrumVisible(
                "dashboard-media-card", artSlot.cardOnScreen)
            Component.onDestruction: VisualizerService.setSpectrumVisible(
                "dashboard-media-card", false)

            ClippingRectangle {
                id: artCircle
                anchors.centerIn: parent
                width: artSlot.circleDiameter
                height: artSlot.circleDiameter
                radius: width / 2
                color: Theme.surfaceContainerHigh

                Image {
                    id: dashboardArtwork
                    anchors.fill: parent
                    source: MediaService.artwork
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    visible: artSlot.artReady

                    // Vinyl spin -- subtle, art-only (the circle mask itself
                    // never moves). A square image filling a circular clip
                    // still fully covers that circle at any rotation (the
                    // incircle of a square is rotation-invariant about its
                    // own centre), so this can spin freely without ever
                    // exposing a corner. `paused`, not toggling `running`,
                    // so pausing playback freezes it in place instead of
                    // snapping back to 0 on the next play.
                    NumberAnimation on rotation {
                        from: 0
                        to: 360
                        duration: 40000
                        loops: Animation.Infinite
                        running: true
                        paused: !artSlot.ringSpinning
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: !artSlot.artReady
                    text: MediaService.available ? "󰝚" : "󰎆"
                    color: AdaptiveColor.activeFill
                    font.family: Config.appearance.monoFontFamily
                    font.pixelSize: 36
                }
            }

            // Circular visualizer ring, wrapping just outside the art.
            // A Repeater of thin rounded Rectangles (GPU-composited, no
            // Canvas repaint) rather than a Shape/path -- see
            // services/VisualizerService.qml's `spectrum` (64-bin cava
            // feed, own process/config, gated by anySpectrumVisible above)
            // for the data. Faded/scaled out whenever nothing is playing,
            // same as island/Eq.qml's own "absent when nothing is playing"
            // rule -- a static ring on an idle/paused dashboard would just
            // be decoration, which the de-bento brief for this card
            // explicitly rules out.
            Item {
                id: ring
                anchors.centerIn: parent
                width: artSlot.ringOuter
                height: artSlot.ringOuter

                // Fade + scale in on play, out on pause/stop -- instead of
                // popping in at full size, which read as a glitch rather
                // than an intentional appearance. `visible` stays true for
                // the whole fade-out (not flipped the instant playback
                // stops) so the Behavior actually gets to animate.
                readonly property bool shown: MediaService.playing
                opacity: ring.shown ? 1 : 0
                scale: ring.shown ? 1 : 0.85
                visible: ring.opacity > 0.001
                Behavior on opacity {
                    NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
                }
                Behavior on scale {
                    NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
                }

                // One revolution per ~20s, constant and smooth. `paused`
                // (not `running`) so stopping playback freezes the ring in
                // place -- it resumes spinning from wherever it stopped
                // instead of snapping back to 0.
                NumberAnimation on rotation {
                    from: 0
                    to: 360
                    duration: 20000
                    loops: Animation.Infinite
                    running: true
                    paused: !artSlot.ringSpinning
                }

                Repeater {
                    model: VisualizerService.spectrumBarCount
                    delegate: Rectangle {
                        id: bar
                        required property int index
                        readonly property real angle:
                            (index / VisualizerService.spectrumBarCount)
                                * 2 * Math.PI - Math.PI / 2
                        readonly property real level: VisualizerService
                            .spectrum[index] || 0
                        readonly property real radiusOut:
                            artSlot.circleDiameter / 2 + artSlot.ringGap

                        width: artSlot.barWidth
                        height: artSlot.barMinLen
                            + (artSlot.barMaxLen - artSlot.barMinLen)
                                * Math.max(0, Math.min(1, level))
                        radius: width / 2
                        color: AdaptiveColor.activeFill

                        // Bottom-anchored at a fixed point on the ring
                        // radius (recomputed off `height` so growth reads
                        // outward, not from the centre), then rotated about
                        // that same point so the bar's long axis points
                        // radially instead of staying axis-aligned.
                        x: ring.width / 2 + bar.radiusOut * Math.cos(bar.angle)
                            - bar.width / 2
                        y: ring.height / 2 + bar.radiusOut * Math.sin(bar.angle)
                            - bar.height
                        transformOrigin: Item.Bottom
                        rotation: bar.angle * 180 / Math.PI + 90

                        Behavior on height {
                            NumberAnimation {
                                duration: 90
                                easing.type: Easing.OutQuad
                            }
                        }
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            // Figma "Media meta" (9:5): flex column, 6px gap.
            spacing: Theme.u(6 / 44)

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: "NOW PLAYING"
                    color: AdaptiveColor.glassTextDim
                    font.family: Config.appearance.handFontFamily
                    font.pixelSize: Theme.dashLabel
                }
                Text {
                    text: "Media ›"
                    color: AdaptiveColor.activeFill
                    font.family: Config.appearance.fontFamily
                    font.pixelSize: Theme.dashCaption
                }
            }
            // Figma "spacer" (9:9): 20px tall, on top of the ColumnLayout's
            // own 6px gap either side of it.
            Item { Layout.preferredHeight: Theme.u(20 / 44) }
            Text {
                Layout.fillWidth: true
                text: MediaService.available ? MediaService.title : "Nothing playing"
                color: AdaptiveColor.glassText
                elide: Text.ElideRight
                font.family: Config.appearance.handFontFamily
                font.pixelSize: Theme.dashTitle
                style: Theme.dashHeavy
                styleColor: AdaptiveColor.glassText
            }
            Text {
                Layout.fillWidth: true
                text: MediaService.available
                    ? MediaService.artist : "Playback will appear here"
                color: AdaptiveColor.glassTextDim
                elide: Text.ElideRight
                font.family: Config.appearance.fontFamily
                font.pixelSize: Theme.dashLabel
            }

            // Straight progress bar -- the owner's Figma (node 9:3) draws
            // this flat, unlike the WaveTrack used on the hover/media-popup
            // pills elsewhere in this shell.
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 3

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: Qt.alpha(AdaptiveColor.glassText, 0.14)
                }
                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width
                        * Math.max(0, Math.min(1, MediaService.progress))
                    radius: height / 2
                    color: AdaptiveColor.activeFill
                }
            }

            Item { Layout.fillHeight: true }

            // Centred lyrics area -- empty (and therefore invisible) with
            // no active lyric, never a stale leftover line.
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: LyricsService.active ? LyricsService.currentLine : ""
                color: AdaptiveColor.glassText
                font.family: Config.appearance.handFontFamily
                font.pixelSize: Theme.dashCaption
            }

            Item { Layout.fillHeight: true }
        }
    }
}
