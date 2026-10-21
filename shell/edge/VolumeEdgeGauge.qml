import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"

/**
 * VolumeEdgeGauge -- the edge-scroll volume OSD (edge/VolumeEdgeStrip.qml
 * drives it). One PanelWindow per outer edge, spanning the full screen
 * height so the gauge itself can be positioned at any y via explicit
 * maths (never anchors), clamped on-screen.
 *
 * MORPH, NOT SLIDE (owner feedback: "the volume container doesn't morph
 * out of the corners" -- it must be flush against the screen edge and
 * flare into it, Caelestia-drawer style). The panel (edge/
 * EdgePanelShape.qml) is flush against the docked screen edge at all
 * times (zero gap); what animates is its own DEPTH (protrusion away from
 * the edge) and LENGTH (extent along the edge), each its own MotionValue,
 * not a floating rect's opacity/x. At depth 0 the shape has ~zero area,
 * so there is no floating sliver and no separate opacity to "pop" --
 * hiding is purely geometric.
 *
 * The window itself must be wide enough to hold the fillet at full depth
 * (EdgePanelShape's outer radius) -- implicitWidth is exactly the max
 * depth, no separate edge-gap margin, since the concave fillets live
 * entirely within that depth range already.
 *
 * Fully click-through (empty mask): this is a readout, never an input
 * surface, so it can never steal a hover/click meant for whatever's under
 * it once it's grown out over real content.
 */
PanelWindow {
    id: window

    required property string dockEdge   // "left" or "right"

    property real level: 0
    property bool muted: false
    // Local Y (screen pixels) of the wheel event that last drove this
    // gauge -- set by VolumeEdgeStrip, which shares this screen's full
    // height, so its wheel.y is already in the same coordinate space.
    property real cursorY: screen ? screen.height / 2 : 0

    color: "transparent"
    WlrLayershell.namespace: "qml-rice:volume-edge-gauge-" + dockEdge
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    mask: Region {}

    anchors {
        top: true
        bottom: true
        left: dockEdge === "left"
        right: dockEdge === "right"
    }

    readonly property real _gaugeDepth: Theme.u(1.6)     // full protrusion
    readonly property real _gaugeLength: Theme.u(4.2)    // full extent along edge
    readonly property real _cornerR: Theme.u(0.45)
    // Hidden length is "about the fillet size" (owner spec) -- enough for
    // both fillets to still read as fillets, not a floating sliver.
    readonly property real _hiddenLength: _cornerR

    implicitWidth: _gaugeDepth

    property bool shown: false

    // Depth: smooth, no overshoot -- a bulge popping past full depth would
    // read as the panel poking through the bezel.
    MotionValue {
        id: depthMV
        unit: "px"
        omega: Motion.presetSmooth().omega
        zeta: Motion.presetSmooth().zeta
        target: window.shown ? window._gaugeDepth : 0
    }
    // Length: slight overshoot, matching the pill's own bouncy morph tuning
    // (core/Motion.qml presetBouncy -- response 0.5s, zeta 0.75, ~2.8%
    // overshoot).
    MotionValue {
        id: lengthMV
        unit: "px"
        omega: Motion.presetBouncy().omega
        zeta: Motion.presetBouncy().zeta
        target: window.shown ? window._gaugeLength : window._hiddenLength
    }

    visible: depthMV.value > 0.5

    Timer {
        id: hideTimer
        interval: 1200
        onTriggered: window.shown = false
    }

    /** Called by VolumeEdgeStrip on every wheel-driven volume change. */
    function notifyActivity(localY: real): void {
        cursorY = localY
        shown = true
        hideTimer.restart()
    }

    readonly property real _length: lengthMV.value
    readonly property real _restY: {
        const raw = window.cursorY - _length / 2
        const maxY = Math.max(0, window.height - _length)
        return Math.max(0, Math.min(maxY, raw))
    }

    // Concave edge-fillets collapse to 0 as the panel nears a physical
    // screen corner (owner spec: "if it clamps flush with the screen
    // corner, the fillet on that side merges into the corner"). Ramps
    // linearly over the last `_cornerR` px of travel so it never pops.
    readonly property real _topFillet: _cornerR
        * Math.max(0, Math.min(1, _restY / Math.max(1, _cornerR)))
    readonly property real _bottomFillet: _cornerR
        * Math.max(0, Math.min(1,
            (window.height - (_restY + _length)) / Math.max(1, _cornerR)))

    // Content stagger: fades in once the shape is ~60% out, fades out
    // immediately on hide (well before the depth spring finishes
    // retracting) -- same staggered-reveal shape as island/Reveal.qml's
    // expanded content, just without needing its per-item ordering.
    readonly property real depthProgress: window._gaugeDepth > 0
        ? depthMV.value / window._gaugeDepth : 0
    property bool _contentShown: false
    onDepthProgressChanged: {
        if (window.shown && depthProgress >= 0.6)
            _contentShown = true
    }
    onShownChanged: if (!window.shown) _contentShown = false

    // Explicit x/y maths throughout -- this whole item moves continuously
    // (depth, length, y all animate), so no anchors.

    EdgePanelShape {
        id: panel
        dockEdge: window.dockEdge
        cornerRadius: window._cornerR
        topFillet: window._topFillet
        bottomFillet: window._bottomFillet
        fillColor: Theme.surfaceContainer

        width: depthMV.value
        height: lengthMV.value
        x: window.dockEdge === "left" ? 0 : window.width - width
        y: window._restY
    }

    // Clipped to the SAME flared silhouette as `panel`, via Canvas clip()
    // inside SloshGauge itself (edge/SloshGauge.qml's _edgeFlarePath) --
    // NOT a QtQuick.Effects MultiEffect mask. That was tried first and
    // dropped: it did not reliably clip content to `panel` in this shell's
    // render pipeline, and Canvas-based clipping is what every other gauge
    // here already uses (SloshGauge's own header comment).
    Item {
        id: contentClip
        x: panel.x
        y: panel.y
        width: panel.width
        height: panel.height
        visible: width > 1 && height > 1
        opacity: window._contentShown ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: window._contentShown ? 160 : 100
                easing.type: Easing.OutCubic
            }
        }

        SloshGauge {
            anchors.fill: parent
            level: window.level
            muted: window.muted
            dockEdge: window.dockEdge
            cornerRadius: window._cornerR
            topFillet: window._topFillet
            bottomFillet: window._bottomFillet
        }
    }
}
