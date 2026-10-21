// Offscreen render harness for the pill workspace-switch overlay and the
// launcher workspace toast -- modelled on render-dashboard.qml (FloatingWindow
// + grabToImage(), no screen capture, no live shell). Never touches the real
// desktop: HyprlandService's underlying Hyprland singleton is read-only here
// and nothing in this file dispatches a workspace switch or opens the real
// launcher -- the arc is driven purely by calling WorkspacePillRow.travelTo()
// directly, and the toast by instantiating WorkspaceToastCard directly.
//
// Run with: qs -p ./render-workspaces.qml
import QtQuick
import Quickshell
import "core"
import "island"
import "services"

FloatingWindow {
    id: window
    title: "workspace render harness"
    implicitWidth: 420
    implicitHeight: 300

    Rectangle {
        id: grabRoot
        anchors.fill: parent
        color: "#0b0b0e"

        Column {
            anchors.centerIn: parent
            spacing: 28

            // ---- 1. Resting pill mid-arc ------------------------------
            Rectangle {
                id: pillMock
                width: 200; height: 40
                radius: 20
                color: "#1c1a22"
                WorkspacePillRow {
                    id: row
                    anchors.centerIn: parent
                    maxWorkspaces: 6
                    previousWorkspaceId: 2
                }
            }

            // ---- 2. Launcher workspace toast ----------------------------
            Rectangle {
                width: 240; height: 70
                radius: 12
                color: "#0b0b0e"
                WorkspaceToastCard {
                    id: toast
                    anchors.centerIn: parent
                    workspaceId: 4
                }
            }
        }
    }

    Component.onCompleted: {
        // Put the arc dot mid-flight from slot 2 -> slot 5, driven by hand,
        // since without a live Hyprland session HyprlandService's own
        // onContextChanged never fires on its own.
        row.travelTo(5)
        for (let i = 0; i < 15; i++) row.dotX.step(Motion.h)
        const midValue = row.dotX.value
        const midVelocity = row.dotX.velocity
        console.log("mid-flight snapshot: dotX=" + midValue.toFixed(2)
            + " arcStart=" + row.arcStartX.toFixed(2)
            + " arcTarget=" + row.arcTargetX.toFixed(2)
            + " arcY=" + row.arcY.toFixed(2))
        Qt.callLater(function() {
            // The shared Motion clock's own real-time FrameAnimation gets at
            // least one more tick across this event-loop turn (grabToImage
            // is async), which would otherwise carry the spring further
            // towards rest before the actual screenshot. Re-pin the exact
            // snapshot taken above right before grabbing: setting
            // .value/.velocity does NOT touch .target, so it can't re-enter
            // MotionValue's onTargetChanged registration path.
            row.dotX.value = midValue
            row.dotX.velocity = midVelocity
            row.dotX.active = true
            grabRoot.grabToImage(function(result) {
                result.saveToFile("/tmp/qml-rice-workspace-arc.png")
                console.log("SAVED arc " + result.image.width + "x" + result.image.height)
                midArcTimer.start()
            })
        })
    }

    Timer {
        id: midArcTimer
        interval: 900   // toast now well into its hold window (~1000ms in)
        onTriggered: {
            grabRoot.grabToImage(function(result) {
                result.saveToFile("/tmp/qml-rice-workspace-toast.png")
                console.log("SAVED toast " + result.image.width + "x" + result.image.height)
                Qt.exit(0)
            })
        }
    }
}
