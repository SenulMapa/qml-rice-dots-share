import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"
import "../services"

/**
 * VolumeEdgeStrip -- one instance per outer screen edge (see shell.qml's
 * Variants over core/EdgeGeometry.instancesFor). A hairline invisible
 * layer-shell strip that only exists to catch wheel events, plus the
 * VolumeEdgeGauge OSD it drives.
 *
 * Top layer, not Overlay: a fullscreen game legitimately covers this, same
 * as it covers everything else on Top (feature spec) -- edge-scroll volume
 * is a desktop convenience, not something that should punch through a game.
 *
 * 2px wide. Quickshell's Region mask has no "wheel-only" granularity -- it
 * either claims the whole masked rect for all pointer input or none of it
 * (checked: WorkspaceToast/EdgeVisualizer's own mask comments, and there is
 * no separate wheel-region API) -- so the strip is kept hairline-thin
 * instead, minimising how much cursor travel it can intercept from
 * whatever's normally at that edge.
 */
PanelWindow {
    id: strip

    required property string dockEdge   // "left" or "right"

    color: "transparent"
    WlrLayershell.namespace: "qml-rice:volume-edge-strip-" + dockEdge
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0

    anchors {
        top: true
        bottom: true
        left: dockEdge === "left"
        right: dockEdge === "right"
    }
    implicitWidth: 2

    mask: Region { width: strip.width; height: strip.height }

    // Wheel-notch accumulator, in Qt angleDelta units (120 per physical
    // detent). Touchpads emit many small deltas instead of one 120-unit
    // notch, so this just keeps accumulating either way and only commits
    // whole Config.volumeEdge.step increments -- fractional touchpad
    // motion carries over to the next event instead of being dropped.
    property real _accumY: 0

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            strip._accumY += event.angleDelta.y
            const notch = 120
            while (Math.abs(strip._accumY) >= notch) {
                const dir = strip._accumY > 0 ? 1 : -1
                strip._accumY -= dir * notch
                // Scroll up (positive angleDelta.y) => louder.
                AudioService.setVolumeFromEdge(
                    AudioService.volumePercent + dir * Config.volumeEdge.step)
            }
            gauge.notifyActivity(event.y)
        }
    }

    VolumeEdgeGauge {
        id: gauge
        screen: strip.screen
        dockEdge: strip.dockEdge
        level: AudioService.volumePercent
        muted: AudioService.muted
    }
}
