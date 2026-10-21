// Component test for island/IslandNotification.qml's countdown: pausing
// preserves the remaining time instead of restarting it, and unpausing
// resumes from there -- QML's own `paused` property does this for free, so
// this test is really proving the wiring uses it correctly end to end.
//
// Driven against mock service/controller objects exposing the same surface
// as services/NotificationService.qml and island/IslandController.qml (see
// IslandNotification.qml's header comment) -- neither the real
// NotificationService (which would try to register a live D-Bus notification
// server) nor a real IslandController is ever touched.
import QtQuick
import Quickshell
import "island"

ShellRoot {
    id: root
    property var log: []
    property real savedProgress: 0
    function ok(name, cond, detail) {
        log.push((cond ? "PASS  " : "FAIL  ") + name + (detail ? "   " + detail : ""))
    }

    QtObject {
        id: mockController
        property string visualState: "dormant"
        readonly property string notification: "notification"
        property int expireCount: 0
        function expireTransientNotification(): void { expireCount++ }
    }

    QtObject {
        id: mockService
        property var current: null
        function visibleActions(entry): var { return [] }
        function plainText(value): string { return value || "" }
        function activate(entry): bool { return false }
        function dismissTransient(): void {}
        function invokeAction(entry, index): void {}
    }

    PanelWindow {
        id: win
        anchors { top: true; left: true }
        implicitWidth: 420
        implicitHeight: 100
        exclusiveZone: 0
        color: "transparent"

        IslandNotification {
            id: popup
            anchors.fill: parent
            service: mockService
            controller: mockController
        }
    }

    SequentialAnimation {
        running: true

        ScriptAction { script: {
            mockService.current = {
                id: 1, appName: "Test", title: "Hello", body: "",
                critical: false, actions: []
            }
            mockController.visualState = "notification"
        } }
        PauseAnimation { duration: 60 }
        ScriptAction { script: {
            root.ok("countdown_started", popup.progress < 1 && popup.progress > 0,
                "progress=" + popup.progress.toFixed(3))
        } }

        ScriptAction { script: { popup.testHovered = true } }
        PauseAnimation { duration: 40 }
        ScriptAction { script: { root.savedProgress = popup.progress } }
        PauseAnimation { duration: 150 }
        ScriptAction { script: {
            root.ok("paused_preserves_progress",
                Math.abs(popup.progress - root.savedProgress) < 0.01,
                "before=" + root.savedProgress.toFixed(3)
                    + " after=" + popup.progress.toFixed(3))
        } }

        ScriptAction { script: { popup.testHovered = false } }
        PauseAnimation { duration: 30 }
        ScriptAction { script: {
            root.ok("resume_continues_not_restarts",
                popup.progress < root.savedProgress && popup.progress > 0,
                "saved=" + root.savedProgress.toFixed(3)
                    + " now=" + popup.progress.toFixed(3))
            root.ok("no_premature_expiry", mockController.expireCount === 0,
                "expireCount=" + mockController.expireCount)
        } }

        ScriptAction { script: {
            console.log("=== NOTIFICATION COUNTDOWN TEST ===")
            for (const line of root.log) console.log(line)
            const failed = root.log.filter(l => l.indexOf("FAIL") === 0).length
            console.log("=== " + (root.log.length - failed) + "/" + root.log.length + " passed ===")
            Qt.exit(failed === 0 ? 0 : 1)
        } }
    }
}
