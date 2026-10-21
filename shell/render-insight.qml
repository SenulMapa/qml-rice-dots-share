// Offscreen render harness for the InsightCenter/dashboard polish pass
// (panels/InsightCenter.qml's directional carousel + per-page focal-point
// changes, panels/Dashboard.qml's quick-strip micro-interactions). Modelled
// on render-dashboard.qml: real components, real live services, grabToImage
// only -- no screen capture, no live-state writes (page/tab selection is
// local UI state; nothing here touches audio/network/wallpaper/player).
//
// Run with: qs -p ./render-insight.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import "core"
import "panels"

FloatingWindow {
    id: window
    title: "insight render harness"
    implicitWidth: 850
    implicitHeight: 950

    readonly property string tag: (Quickshell.env("INSIGHTRENDER_TAG") || "render")

    Rectangle {
        id: grabRoot
        anchors.fill: parent
        color: "#121217"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 16

            Rectangle {
                id: insightFrame
                Layout.preferredWidth: 789
                Layout.preferredHeight: 460
                color: "#17151b"
                radius: 12
                clip: true

                InsightCenter {
                    id: insight
                    anchors.fill: parent
                    anchors.margins: 10
                }
            }

            Rectangle {
                id: dashboardFrame
                Layout.preferredWidth: 789
                Layout.preferredHeight: 440
                color: "#121217"
                radius: 12
                clip: true

                Dashboard {
                    id: dashboard
                    anchors.fill: parent
                    anchors.margins: 8
                }
            }
        }
    }

    function grab(name) {
        grabRoot.grabToImage(function(result) {
            const path = "/tmp/polish-shots/insight-" + name + ".png"
            if (result.saveToFile(path))
                console.log("SAVED " + path)
            else
                console.log("SAVE_FAILED " + path)
        })
    }

    // Let async artwork/icon fonts/live services settle before the first
    // grab, same margin render-dashboard.qml uses. Every timer explicitly
    // starts the next one in its own handler -- one consistent chain, no
    // autostart-ordering assumptions.
    Timer { id: t0; interval: 1000; running: true; repeat: false
        onTriggered: { window.grab("00-weather"); t1.start() } }
    Timer { id: t1; interval: 120; running: false; repeat: false
        onTriggered: { insight.selectedPage = "calendar"; t2.start() } }
    Timer { id: t2; interval: 400; running: false; repeat: false
        onTriggered: { window.grab("01-calendar"); t3.start() } }
    Timer { id: t3; interval: 120; running: false; repeat: false
        onTriggered: { insight.selectedPage = "media-center"; t4.start() } }
    Timer { id: t4; interval: 400; running: false; repeat: false
        onTriggered: { window.grab("02-media"); t5.start() } }
    Timer { id: t5; interval: 120; running: false; repeat: false
        onTriggered: { insight.selectedPage = "system"; t6.start() } }
    Timer { id: t6; interval: 400; running: false; repeat: false
        onTriggered: { window.grab("03-system"); t7.start() } }
    Timer { id: t7; interval: 500; running: false; repeat: false
        onTriggered: { window.grab("04-overview"); t8.start() } }
    Timer { id: t8; interval: 300; running: false; repeat: false
        onTriggered: Qt.quit() }
}
