import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"

/**
 * MediaCard - the control-centre media card. Reuses MediaService (playback,
 * artwork, position) and LyricsService (synced lines) rather than
 * reimplementing either; WaveTrack still draws the progress bar, per the
 * owner's standing request that overrides the prototype's plain bar.
 *
 * The card is hidden entirely with no MPRIS player. Height is a
 * MotionValue spring -- like island/Island.qml's own surface -- not a
 * duration clip, and only expands when LyricsService actually has lines for
 * the current track: `onCanExpandChanged` collapses it the instant a track
 * with no lyrics starts playing.
 */
Item {
    id: root

    readonly property bool canExpand: LyricsService.lines.length > 0
    property bool expanded: false

    readonly property real collapsedHeight: Theme.u(2.4)
    readonly property real expandedHeightTarget: Theme.u(5.66)

    readonly property string previousLyric: LyricsService.index > 0
        ? (LyricsService.lines[LyricsService.index - 1].text || LyricsService.noteGlyph) : ""
    readonly property string currentLyric: LyricsService.index >= 0
        && LyricsService.index < LyricsService.lines.length
        ? (LyricsService.lines[LyricsService.index].text || LyricsService.noteGlyph)
        : LyricsService.noteGlyph
    readonly property string nextLyric: LyricsService.index >= 0
        && LyricsService.index + 1 < LyricsService.lines.length
        ? (LyricsService.lines[LyricsService.index + 1].text || LyricsService.noteGlyph) : ""

    visible: MediaService.available
    implicitHeight: heightMV.value

    onCanExpandChanged: if (!canExpand) root.expanded = false
    onVisibleChanged: if (!visible) root.expanded = false

    property MotionValue heightMV: MotionValue {
        unit: "px"
        zeta: 0.92
        omega: 12.8 / Math.max(0.25, Config.appearance.motionScale)
        target: root.expanded && root.canExpand
            ? root.expandedHeightTarget : root.collapsedHeight
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: Theme.u(0.34)
        clip: true
        color: Theme.surfaceContainerHigh

        Rectangle {
            anchors.fill: parent
            visible: !artwork.visible
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.surfaceContainerHigh }
                GradientStop { position: 1.0; color: Theme.surfaceContainer }
            }
        }

        Image {
            id: artwork
            anchors.fill: parent
            source: MediaService.artwork
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
            visible: status === Image.Ready
        }

        Rectangle {
            anchors.fill: parent
            visible: artwork.visible
            color: Qt.alpha(Theme.surface, 0.55)
        }

        RowLayout {
            id: deviceRow
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.leftMargin: Theme.u(0.3)
            anchors.topMargin: Theme.u(0.22)
            spacing: Theme.u(0.1)

            Text {
                text: "󰓃"
                color: Theme.surfaceVariantText
                font.family: Config.appearance.monoFontFamily
                font.pixelSize: Theme.u(0.24)
            }
            Text {
                text: AudioService.outputName
                color: Theme.surfaceVariantText
                font.family: Config.appearance.fontFamily
                font.pixelSize: Theme.u(0.22)
                elide: Text.ElideRight
            }
        }

        ColumnLayout {
            anchors.left: parent.left
            anchors.right: playButton.left
            anchors.top: deviceRow.bottom
            anchors.leftMargin: Theme.u(0.3)
            anchors.rightMargin: Theme.u(0.2)
            anchors.topMargin: Theme.u(0.1)
            visible: !root.expanded || !root.canExpand
            spacing: 2

            Text {
                Layout.fillWidth: true
                text: MediaService.title
                color: Theme.surfaceText
                elide: Text.ElideRight
                font.family: Config.appearance.displayFontFamily
                font.pixelSize: Theme.u(0.46)
                font.weight: Font.Normal
            }
            Text {
                Layout.fillWidth: true
                text: MediaService.artist
                color: Theme.surfaceVariantText
                elide: Text.ElideRight
                font.family: Config.appearance.fontFamily
                font.pixelSize: Theme.u(0.26)
            }
        }

        ColumnLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: deviceRow.bottom
            anchors.topMargin: Theme.u(0.2)
            anchors.leftMargin: Theme.u(0.4)
            anchors.rightMargin: Theme.u(0.4)
            visible: root.expanded && root.canExpand
            opacity: visible ? 1 : 0
            spacing: Theme.u(0.14)

            Text {
                Layout.fillWidth: true
                text: MediaService.title
                color: Theme.surfaceText
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                font.family: Config.appearance.displayFontFamily
                font.pixelSize: Theme.u(0.4)
                font.weight: Font.Normal
            }

            Text {
                Layout.fillWidth: true
                Layout.topMargin: Theme.u(0.2)
                text: root.previousLyric
                color: Theme.surfaceText
                opacity: 0.35
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                font.family: Config.appearance.displayFontFamily
                font.pixelSize: Theme.u(0.34)
            }
            Text {
                Layout.fillWidth: true
                text: root.currentLyric
                color: Theme.surfaceText
                opacity: 1
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                font.family: Config.appearance.displayFontFamily
                font.pixelSize: Theme.u(0.34)
            }
            Text {
                Layout.fillWidth: true
                text: root.nextLyric
                color: Theme.surfaceText
                opacity: 0.35
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                font.family: Config.appearance.displayFontFamily
                font.pixelSize: Theme.u(0.34)
            }
        }

        Rectangle {
            id: playButton
            // Movement onto the shared MotionValue spring primitive (see
            // core/Motion.qml/core/MotionValue.qml) instead of duration
            // Behaviors, so an expand/collapse tap mid-transition carries
            // velocity through instead of restarting. Enter (growing/
            // moving toward the expanded position) uses Motion's slightly
            // underdamped preset; exit (collapsing back) uses its
            // critically-damped one -- direction read off each spring's
            // own target-vs-value comparison so x/y/diameter can settle at
            // slightly different times without hand-tracking a shared
            // "opening" flag.
            width: Math.round(diameterMV.value)
            height: Math.round(diameterMV.value)
            radius: width / 2
            color: Theme.surfaceText
            x: Math.round(xMV.value)
            y: Math.round(yMV.value)

            // Direction (entering/exiting) is decided ONCE per leg by
            // MotionValue itself (omegaEnter/omegaExit, locked at
            // retarget time -- see core/MotionValue.qml), not
            // re-derived every frame from `target >= value`: that old
            // pattern flips mid-flight near an overshoot crossing and
            // silently rewrites the ODE's omega/zeta out from under its
            // own basis, which is what read as vibration.
            //
            // x/y ALSO used to target `playButton.diameterMV.value` --
            // another spring's LIVE, still-animating value -- which
            // retargeted x/y from a moving goalpost every single frame
            // (_rebase() every frame means the spring never gets more
            // than one frame's worth of its own trajectory). They now
            // target the diameter's STABLE end state
            // (root.expanded ? Theme.u(1.12) : Theme.u(0.9)) so x/y
            // retarget exactly once per expand/collapse, same as
            // diameterMV itself.
            readonly property real diameterTarget:
                root.expanded ? Theme.u(1.12) : Theme.u(0.9)
            property MotionValue diameterMV: MotionValue {
                unit: "px"
                target: playButton.diameterTarget
                omegaEnter: Motion.omegaEnter / Math.max(0.25, Config.appearance.motionScale)
                zetaEnter: Motion.zetaEnter
                omegaExit: Motion.omegaExit / Math.max(0.25, Config.appearance.motionScale)
                zetaExit: Motion.zetaExit
            }
            property MotionValue xMV: MotionValue {
                unit: "px"
                target: root.expanded
                    ? (card.width - playButton.diameterTarget) / 2
                    : card.width - playButton.diameterTarget - Theme.u(0.3)
                omegaEnter: Motion.omegaEnter / Math.max(0.25, Config.appearance.motionScale)
                zetaEnter: Motion.zetaEnter
                omegaExit: Motion.omegaExit / Math.max(0.25, Config.appearance.motionScale)
                zetaExit: Motion.zetaExit
            }
            property MotionValue yMV: MotionValue {
                unit: "px"
                target: root.expanded
                    ? progressTrack.y - playButton.diameterTarget - Theme.u(0.2)
                    : (card.height - playButton.diameterTarget) / 2
                omegaEnter: Motion.omegaEnter / Math.max(0.25, Config.appearance.motionScale)
                zetaEnter: Motion.zetaEnter
                omegaExit: Motion.omegaExit / Math.max(0.25, Config.appearance.motionScale)
                zetaExit: Motion.zetaExit
            }

            Text {
                anchors.centerIn: parent
                text: MediaService.playing ? "󰏤" : "󰐊"
                color: Qt.alpha(Theme.surface, 0.44)
                font.family: Config.appearance.monoFontFamily
                font.pixelSize: Theme.u(0.4)
            }

            TapHandler { onTapped: MediaService.togglePlaying() }
        }

        WaveTrack {
            id: progressTrack
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: Theme.u(0.3)
            anchors.rightMargin: Theme.u(0.3)
            anchors.bottomMargin: Theme.u(0.22)
            height: 4
            value: MediaService.progress
            playing: MediaService.playing
            accent: Theme.accentFill
            active: root.visible
        }

        TapHandler {
            onTapped: if (root.canExpand) root.expanded = !root.expanded
        }
    }
}
