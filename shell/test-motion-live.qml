// Live proof that core/Motion.qml's FrameAnimation actually advances springs
// inside a running Quickshell and then SLEEPS -- test-motion.qml only ever
// calls step() by hand, so it never exercised the real frame clock.
// A 1x1 transparent PanelWindow supplies the same render loop production has.
import QtQuick
import Quickshell
import "core"
ShellRoot {
    id: root
    property bool sawActive: false
    property real midValue: -1
    PanelWindow {
        anchors { top: true; left: true }
        implicitWidth: 1; implicitHeight: 1
        exclusiveZone: 0
        color: "transparent"
    }
    MotionValue { id: mv; unit: "px" }
    Timer {
        interval: 300; running: true
        onTriggered: { mv.target = 200; root.sawActive = Motion.activeCount > 0 }
    }
    Timer {
        interval: 380; running: true
        onTriggered: root.midValue = mv.value
    }
    Timer {
        interval: 2200; running: true
        onTriggered: {
            const ok = root.sawActive && root.midValue > 0 && root.midValue < 200
                && Math.abs(mv.value - 200) < 0.2 && Motion.activeCount === 0
                && !Motion.clock.running
            console.log("LIVE sawActive=" + root.sawActive + " mid=" + root.midValue.toFixed(2)
                + " final=" + mv.value.toFixed(2) + " activeCount=" + Motion.activeCount
                + " clockRunning=" + Motion.clock.running + " " + (ok ? "PASS" : "FAIL"))
            Qt.quit()
        }
    }
}
