import QtQuick
import QtQuick.Shapes
import "../core"
import "../services"

/**
 * WaveTrack - media progress drawn as a travelling wave, flattening on pause.
 *
 * Same value/accent API as LevelTrack, but a separate component on purpose:
 * LevelTrack also draws the volume/brightness OSD, battery and system-metric
 * bars, none of which should ever wave.
 *
 * Cheap by construction. The wave path is built ONCE per track size, not per
 * frame and not per progress update; while playing, the only per-frame change
 * is a translate. On pause a flat bar crossfades in rather than scaling the
 * wave's amplitude, because scaling would squash the stroke to zero thickness.
 *
 * It animates only while it is really on screen. Some island surfaces hide
 * with enabled:false + opacity:0 instead of visible:false, so gating on
 * `visible` alone would keep the wave animating invisibly for as long as music
 * plays -- the same idle-CPU trap the level meter once fell into. `enabled` and
 * `visible` are both inherited from ancestors, so the gate covers both styles.
 * `active` lets a call site add a stricter on-screen condition when neither
 * applies.
 */
Item {
    id: root

    property real value: 0
    property color accent: AdaptiveColor.activeFill
    property bool playing: false
    property bool active: true

    readonly property bool animating: playing && active && visible && enabled
        && !Config.appearance.reducedMotion
    readonly property real wavelength: 16
    readonly property real stroke: Math.max(2, Math.round(height * 0.5))
    readonly property real amplitudeMax: Math.max(1, Math.min(2.2, height * 0.35))
    // Room above and below so wave peaks are not clipped flat by the window.
    readonly property real pad: amplitudeMax + stroke

    property real phase: 0
    property real amplitude: playing && !Config.appearance.reducedMotion ? 1 : 0
    Behavior on amplitude { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    // Built once per size. Quadratic halves approximate a sine closely enough
    // at this amplitude, and extend two wavelengths past the track so the
    // translate never exposes an edge.
    readonly property string wavePath: {
        const cy = pad + height / 2
        const a = amplitudeMax
        const q = wavelength / 4
        const total = width + wavelength * 2
        let d = "M 0 " + cy
        for (let x = 0; x < total; x += wavelength) {
            d += " Q " + (x + q) + " " + (cy - a) + " " + (x + 2 * q) + " " + cy
            d += " Q " + (x + 3 * q) + " " + (cy + a) + " " + (x + 4 * q) + " " + cy
        }
        return d
    }

    // ---- Ink (Config.appearance.ink) --------------------------------------
    // The played part is built from points rather than the translated
    // Shape above, because the envelope has to stay pinned to the track: it
    // rises 0 -> full over the first inkTaper px and falls full -> 0 over the
    // last inkTaper px before the thumb, so the wave grows out of the line
    // and melts into the flat remainder with no hard edge at either end.
    readonly property bool ink: Config.appearance.ink
    readonly property real inkTaper: 14
    readonly property real inkPlayW: width * Math.max(0, Math.min(1, root.value))
    readonly property real inkAmp: 4 * amplitude
    function inkSmooth(t) {
        const c = Math.max(0, Math.min(1, t))
        return c * c * (3 - 2 * c)
    }
    // Rebuilt while the wave travels (phase) and when the value/amplitude move.
    // ~one point per 2px, so a few hundred points at most per frame.
    readonly property var inkVerts: {
        const cy = root.height / 2
        const pw = root.inkPlayW
        const n = Math.max(1, Math.ceil(pw / 2))
        const pts = []
        for (let i = 0; i <= n; i++) {
            const x = Math.min(pw, i * 2)
            const env = inkSmooth(x / root.inkTaper)
                * inkSmooth((pw - x) / root.inkTaper)
            const y = cy + root.inkAmp * env
                * Math.sin((x + root.phase) * 2 * Math.PI / root.wavelength)
            pts.push(Qt.point(x, y))
        }
        return pts
    }

    implicitHeight: 6

    NumberAnimation on phase {
        running: root.animating
        from: 0
        to: -root.wavelength
        duration: 900
        loops: Animation.Infinite
    }

    Rectangle {
        id: unplayed
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: root.stroke
        radius: height / 2
        color: Qt.alpha(AdaptiveColor.glassTextDim, 0.16)
        visible: !root.ink
    }

    Item {
        id: played
        y: -root.pad
        width: root.width * Math.max(0, Math.min(1, root.value))
        height: root.height + root.pad * 2
        clip: true
        visible: !root.ink
        Behavior on width {
            NumberAnimation { duration: Animations.fast; easing.type: Animations.emphasizedEase }
        }

        Rectangle {
            id: flatPlayed
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: root.stroke
            radius: height / 2
            color: root.accent
            opacity: 1 - root.amplitude
            visible: opacity > 0.01
        }

        Shape {
            id: wave
            x: root.phase
            width: root.width + root.wavelength * 2
            height: parent.height
            opacity: root.amplitude
            visible: opacity > 0.01
            Component.onCompleted: {
                // Analytic antialiasing without allocating an offscreen layer,
                // where this Qt provides it.
                if (Shape.CurveRenderer !== undefined)
                    preferredRendererType = Shape.CurveRenderer
            }
            ShapePath {
                strokeColor: root.accent
                strokeWidth: root.stroke
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: root.wavePath }
            }
        }
    }

    // Playhead: hides the hard clip edge where the wave meets the flat track.
    Rectangle {
        width: root.stroke * 2
        height: width
        radius: width / 2
        color: root.accent
        anchors.verticalCenter: parent.verticalCenter
        x: Math.max(0, played.width - width / 2)
        visible: root.value > 0 && !root.ink
    }

    // ---- Ink track -------------------------------------------------------
    // Remainder: 3px, white at .22, round caps (the rounded end sits under
    // the thumb, so only the far end is visible).
    Rectangle {
        visible: root.ink
        x: root.inkPlayW
        width: Math.max(0, root.width - root.inkPlayW)
        height: 3
        radius: 1.5
        anchors.verticalCenter: parent.verticalCenter
        color: Qt.rgba(1, 1, 1, 0.22)
    }

    Shape {
        id: inkWave
        visible: root.ink && root.value > 0
        anchors.fill: parent
        ShapePath {
            strokeColor: Theme.fillOn
            strokeWidth: 3
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: root.inkVerts }
        }
    }

    // Ink thumb: a 12px fillOn dot on the playhead.
    Rectangle {
        visible: root.ink && root.value > 0
        width: 12
        height: 12
        radius: 6
        color: Theme.fillOn
        anchors.verticalCenter: parent.verticalCenter
        x: root.inkPlayW - 6
    }
}
