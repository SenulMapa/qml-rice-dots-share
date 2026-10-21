// Offscreen render harness for the ported widgets (Phase 2) plus the fixed
// WidgetFrame edit chrome (Phase 1). Modelled on render-dashboard.qml:
// grabToImage() on real component instances with real Theme/Config tokens,
// no screen capture, NOT shell.qml -- this must never open a real
// layer-shell surface on the live desktop (see run-tests.sh's own
// FloatingWindow-based tests for the same convention).
//
// Run with: qs -p ./render-new-widgets.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import "core"
import "widgets"
import "services"

FloatingWindow {
    id: window
    title: "widget render harness"

    // Some window-size default in this environment clamps a FloatingWindow's
    // effective size well below implicitWidth/implicitHeight regardless of
    // what's requested here (measured ~951x514 even when asking for
    // 1400x900) -- rather than fight that, render in two passes selected by
    // RENDER_SET so each pass's total content comfortably fits under that
    // ceiling and nothing gets clipped out of the grabbed frame.
    readonly property string renderSet: Quickshell.env("RENDER_SET") || "a"

    readonly property var allSpecs: [
        { name: "analogClock", w: 200, h: 200, component: analogClockComp, set: "a" },
        { name: "digitalClock", w: 240, h: 150, component: digitalClockComp, set: "a" },
        { name: "calendar", w: 320, h: 340, component: calendarComp, set: "b" },
        { name: "todo", w: 320, h: 340, component: todoComp, set: "b" },
        { name: "widgetFrame-editmode", w: 264, h: 264, component: editFrameComp, set: "c" },
        { name: "editPalette-10chips", w: 460, h: 200, component: editPaletteComp, set: "c" },
        { name: "pomodoro", w: 176, h: 176, component: pomodoroComp, set: "d" },
        { name: "systemMonitor", w: 200, h: 230, component: systemMonitorComp, set: "d" }
    ]
    readonly property var specs: allSpecs.filter(s => s.set === renderSet)

    Component { id: analogClockComp; AnalogClockWidget {} }
    Component { id: digitalClockComp; DigitalClockWidget {} }
    Component { id: calendarComp; CalendarWidget {} }
    Component { id: todoComp; TodoWidget {} }
    Component { id: pomodoroComp; PomodoroWidget {} }
    Component { id: systemMonitorComp; SystemMonitorWidget {} }
    Component { id: editPaletteComp; EditPalette { screenName: "RENDER-HARNESS" } }
    Component {
        id: editFrameComp
        WidgetFrame {
            screenName: "RENDER-HARNESS"
            screenWidth: 1200
            screenHeight: 800
            entry: ({ id: "render-preview", type: "shapeClock", x: 0.05, y: 0.05,
                size: "3x3", options: {} })
        }
    }

    Rectangle {
        id: grabRoot
        anchors.fill: parent
        color: Theme.surface

        Flow {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 24

            Repeater {
                model: window.specs
                Rectangle {
                    required property var modelData
                    width: modelData.w + 20
                    height: modelData.h + 40
                    color: "transparent"

                    Column {
                        anchors.fill: parent
                        spacing: 4

                        Text {
                            text: modelData.name
                            color: Theme.surfaceText
                            font.pixelSize: 14
                        }
                        Item {
                            width: modelData.w
                            height: modelData.h
                            Loader {
                                anchors.fill: parent
                                sourceComponent: modelData.component
                            }
                        }
                    }
                }
            }
        }
    }

    Component.onCompleted: WidgetStore.editMode = true

    property int savedCount: 0
    Timer {
        interval: 2500
        running: true
        onTriggered: {
            const outPath = "/tmp/widget-render/contact-sheet-" + window.renderSet + ".png"
            grabRoot.grabToImage(result => {
                result.saveToFile(outPath)
                console.log("SAVED " + outPath)
                Qt.exit(0)
            })
        }
    }
}
