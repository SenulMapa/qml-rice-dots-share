import QtQuick
import "../core"
import "../services"

/**
 * Eq — four bars, LEFT of the clock, bottom-aligned to its baseline.
 *
 * Measured from the source video: 4 bars, ~3px wide / ~2px gap, 18px cluster,
 * heights 6..16 with the tallest exactly equal to the clock's cap height. It
 * is a level meter, not decoration — which is why it is absent when nothing is
 * playing rather than idling at zero.
 *
 * Driven by cava (services/VisualizerService.qml) whenever it is actually
 * producing output. VisualizerService.qml already does the real damping --
 * sqrt compression, a 30%-toward-group-mean blend, and asymmetric
 * attack/decay smoothing -- so this is calm, musical motion rather than a
 * literal spectrum readout by the time it reaches here. What's left for the
 * render side is cheap: cava only emits a new sample every ~33ms (30fps,
 * scripts/cava/eq.conf), so a single lightweight Behavior per bar
 * interpolates between those samples instead of a visible per-frame stair-
 * step. Scoped to `available` only -- the fallback profile below already
 * animates itself with its own SequentialAnimation, and layering this on
 * top of that would double-smooth it. A small floor (0.15) keeps a bar from
 * fully vanishing between beats.
 *
 * The SequentialAnimation below is now only the FALLBACK profile: it runs
 * whenever VisualizerService.available is false (before cava's first frame,
 * or if cava is missing) instead of always. It is a fire-and-forget
 * decorative loop with no interruption semantics to preserve, so it stays
 * exactly the case Qt's canned animations are good at, and running it here
 * keeps four more springs out of the frame clock's active list.
 */
Row {
    id: root
    property bool active: true
    property real barW: 3
    property real maxH: 16
    property color barColor: AdaptiveColor.activeFill
    readonly property real floor: 0.15

    // Resting profile; also the fallback animation when cava isn't
    // available. Its length IS the bar count -- one number, not two things
    // that could drift apart.
    readonly property var restingProfile: [0.40, 1.00, 0.55, 0.75]
    readonly property int barCount: restingProfile.length
    // The cluster's total footprint is FIXED at the measured 18px -- spacing
    // is the thing that's derived from it, not the other way round, so the
    // slot's width never depends on bar count or bar width.
    readonly property real slotWidth: 18
    readonly property real barSpacing: barCount > 1
        ? (slotWidth - barCount * barW) / (barCount - 1) : 0

    spacing: barSpacing
    // Fixed height: bars grow inside it from the bottom. A Row sized to its
    // tallest bar changed height every cava frame, and the centred row it
    // sits in (clock, lyrics) bounced vertically with it.
    height: maxH
    opacity: active ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    Repeater {
        model: root.restingProfile
        delegate: Rectangle {
            id: bar
            property real restingHeight: root.maxH * modelData

            width: root.barW
            radius: root.barW / 2
            color: root.barColor
            anchors.bottom: parent ? parent.bottom : undefined

            height: VisualizerService.available
                ? root.maxH * (root.floor + (1 - root.floor)
                    * (VisualizerService.levels[index] || 0))
                : bar.restingHeight

            Behavior on height {
                enabled: VisualizerService.available
                NumberAnimation { duration: 70; easing.type: Easing.OutQuad }
            }

            SequentialAnimation on restingHeight {
                running: root.active && !VisualizerService.available
                loops: Animation.Infinite
                NumberAnimation {
                    to: root.maxH * (0.25 + 0.75 * modelData)
                    duration: 380 + index * 90
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    to: root.maxH * (0.95 * modelData)
                    duration: 420 + index * 70
                    easing.type: Easing.InOutSine
                }
            }
        }
    }
}
