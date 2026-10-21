// DEPRECATED: Old widget system. Use desktop/ instead
import QtQuick
import "../core"
import "../services"
import "../components"

/**
 * WidgetFrame -- positions one persisted widget entry on its screen and,
 * only while WidgetStore.editMode is on, adds drag-to-move (grid-snapped),
 * a resize-variant cycle button and a remove button. Outside edit mode this
 * is just a positioned Item with a static Loader inside -- no MouseArea, no
 * per-frame cost.
 */
Item {
    id: frame

    required property string screenName
    required property var entry
    required property real screenWidth
    required property real screenHeight

    readonly property var pixelSize: WidgetStore.widgetPixelSize(entry.size)
    width: pixelSize.width
    height: pixelSize.height
    x: entry.x * screenWidth
    y: entry.y * screenHeight

    opacity: 0
    Component.onCompleted: opacity = 1
    Behavior on opacity {
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }

    function cycleSize(): void {
        const keys = Object.keys(WidgetStore.sizeVariants)
        const index = keys.indexOf(frame.entry.size)
        const next = keys[(index + 1) % keys.length]
        WidgetStore.resizeWidget(frame.screenName, frame.entry.id, next)
    }

    function commitDragPosition(): void {
        const snapped = WidgetStore.snapPositionPx(frame.x, frame.y,
            frame.screenWidth, frame.screenHeight, frame.width, frame.height,
            WidgetStore.gridSize)
        frame.x = snapped.x
        frame.y = snapped.y
        WidgetStore.moveWidgetFraction(frame.screenName, frame.entry.id,
            snapped.x / frame.screenWidth, snapped.y / frame.screenHeight)
    }

    // ---- widget content: exactly one Loader active per entry.type -------
    Loader {
        anchors.fill: parent
        active: frame.entry.type === "shapeClock"
        sourceComponent: ShapeClockWidget { anchors.fill: parent }
    }
    Loader {
        anchors.fill: parent
        active: frame.entry.type === "dateWeather"
        sourceComponent: DateWeatherWidget { anchors.fill: parent }
    }
    Loader {
        anchors.fill: parent
        active: frame.entry.type === "media" && MediaService.playing
        sourceComponent: MediaWidget { anchors.fill: parent }
    }
    Loader {
        anchors.fill: parent
        active: frame.entry.type === "batteryRing" && BatteryService.available
        sourceComponent: BatteryRingWidget { anchors.fill: parent }
    }
    Loader {
        anchors.fill: parent
        active: frame.entry.type === "analogClock"
        sourceComponent: AnalogClockWidget { anchors.fill: parent }
    }
    Loader {
        anchors.fill: parent
        active: frame.entry.type === "digitalClock"
        sourceComponent: DigitalClockWidget { anchors.fill: parent }
    }
    Loader {
        anchors.fill: parent
        active: frame.entry.type === "calendar"
        sourceComponent: CalendarWidget { anchors.fill: parent }
    }
    Loader {
        anchors.fill: parent
        active: frame.entry.type === "todo"
        sourceComponent: TodoWidget { anchors.fill: parent }
    }
    Loader {
        anchors.fill: parent
        active: frame.entry.type === "pomodoro"
        sourceComponent: PomodoroWidget { anchors.fill: parent }
    }
    Loader {
        anchors.fill: parent
        active: frame.entry.type === "systemMonitor"
        sourceComponent: SystemMonitorWidget { anchors.fill: parent }
    }

    // ---- edit chrome: only instantiated while editing --------------------
    Loader {
        anchors.fill: parent
        active: WidgetStore.editMode
        sourceComponent: Item {
            anchors.fill: parent

            Squircle {
                anchors.fill: parent
                color: "transparent"
                radius: Theme.radiusMedium
                borderWidth: 2
                borderColor: Theme.primary
            }

            MouseArea {
                anchors.fill: parent
                drag.target: frame
                onReleased: frame.commitDragPosition()
            }

            // NOTE: these buttons must stay fully INSIDE frame's own
            // width/height. WidgetLayer's click-through mask (see
            // widgets/WidgetLayer.qml) is built from this exact WidgetFrame
            // item's geometry -- any child rendered past that geometry
            // (the previous -6 negative anchors.margins pushed each button
            // half outside the frame's top/right edge) is visible but sits
            // OUTSIDE the layer-shell input region, so roughly a quarter of
            // each button (including the corner users aim for first) never
            // received clicks. Positive margins keep the whole hit-target
            // inside the masked area.
            Rectangle {
                width: 22
                height: 22
                radius: 11
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 4
                color: Theme.error
                Text {
                    anchors.centerIn: parent
                    text: "×"
                    color: "white"
                    font.pixelSize: 14
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: WidgetStore.removeWidget(
                        frame.screenName, frame.entry.id)
                }
            }

            Rectangle {
                width: 22
                height: 22
                radius: 11
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                anchors.margins: 4
                color: Theme.primary
                Text {
                    anchors.centerIn: parent
                    text: "⤡"
                    color: "white"
                    font.pixelSize: 12
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: frame.cycleSize()
                }
            }
        }
    }
}
