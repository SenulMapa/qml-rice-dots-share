// Regression test for the WidgetFrame edit-chrome hit-region bug: the
// remove ("x") and resize ("cycle size") buttons used to be placed with
// negative anchors.margins, pushing part of each button PAST the
// WidgetFrame item's own width/height. WidgetLayer's click-through mask
// (widgets/WidgetLayer.qml) is built from that exact item's geometry, so
// any pixel outside it never received input -- roughly a quarter of each
// button, including the very corner a user aims for, was dead. This
// instantiates a real WidgetFrame in edit mode offscreen and asserts every
// visible child Rectangle's mapped bounding box is fully contained within
// the frame's own [0,width] x [0,height] box.
import QtQuick
import Quickshell
import "services"
import "widgets"
import "core"

ShellRoot {
    id: root
    property var log: []
    function ok(name, cond, detail) {
        log.push((cond ? "PASS  " : "FAIL  ") + name + (detail ? "   " + detail : ""))
    }

    FloatingWindow {
        id: window
        visible: false
        implicitWidth: 300
        implicitHeight: 300

        WidgetFrame {
            id: frame
            screenName: "TEST-GEOMETRY-SCREEN"
            screenWidth: 300
            screenHeight: 300
            entry: ({ id: "geom-test", type: "shapeClock", x: 0.1, y: 0.1,
                size: "3x3", options: {} })
        }
    }

    Timer {
        interval: 150
        running: true
        onTriggered: root.runCheck()
    }

    function runCheck() {
        const wasEdit = WidgetStore.editMode
        WidgetStore.editMode = true

        Qt.callLater(() => {
            let allInside = true
            let detail = ""
            function walk(item) {
                for (const child of item.children) {
                    if (child.width > 0 && child.height > 0) {
                        const topLeft = child.mapToItem(frame, 0, 0)
                        const bottomRight = child.mapToItem(frame,
                            child.width, child.height)
                        const inside = topLeft.x >= -0.01 && topLeft.y >= -0.01
                            && bottomRight.x <= frame.width + 0.01
                            && bottomRight.y <= frame.height + 0.01
                        if (!inside) {
                            allInside = false
                            detail += " [" + topLeft.x.toFixed(1) + ","
                                + topLeft.y.toFixed(1) + " -> "
                                + bottomRight.x.toFixed(1) + ","
                                + bottomRight.y.toFixed(1) + " vs frame "
                                + frame.width + "x" + frame.height + "]"
                        }
                    }
                    walk(child)
                }
            }
            walk(frame)
            root.ok("edit_chrome_buttons_stay_inside_frame_mask", allInside, detail)

            WidgetStore.editMode = wasEdit

            console.log("=== WIDGET FRAME GEOMETRY TEST ===")
            for (const line of root.log) console.log(line)
            const failed = root.log.filter(l => l.indexOf("FAIL") === 0).length
            console.log("=== " + (root.log.length - failed) + "/" + root.log.length + " passed ===")
            Qt.exit(failed === 0 ? 0 : 1)
        })
    }
}
