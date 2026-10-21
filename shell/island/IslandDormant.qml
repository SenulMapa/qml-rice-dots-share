import QtQuick
import QtQuick.Layouts
import "../core"

Item {
    id: root
    signal powerRequested()
    // impasto card pages (DeskSettings.islandImpastoCards): forwarded from
    // restClock's own calendarRequested() below.
    signal calendarRequested()
    signal dashboardRequested()
    property bool powerHovered: false
    // Set while the pointer is over island/TimerIndicator.qml, so the
    // surface's own tap does not also open the island.
    property bool timerHovered: false
    // Ink: set by Island.qml; the settings preview leaves it false.
    property bool shareHosted: false
    // Forwarded from IslandController -- see island/IslandRestItem.qml's
    // clockComponent for the actual cross-fade/arc presentation.
    property bool workspaceSwitchActive: false
    property int workspaceIndicatorMax: 5
    property int previousWorkspaceId: 1
    readonly property var displayOrder: Config.island.restItemOrder
    readonly property var leftDisplayOrder: displayOrder.slice(0,
        Math.ceil(displayOrder.length / 2))
    readonly property var rightDisplayOrder: displayOrder.slice(
        Math.ceil(displayOrder.length / 2))

    // The resting pill's real content width: the two side rows, the clock
    // between them, their gaps, and one gap of breathing room at each end.
    // island/IslandController.qml floors the dormant width at this, so a
    // pill holding nothing but a clock is clock-sized instead of always
    // being the configured dormantWidth (which is a floor, not a target --
    // the owner's stored 214 made a clock-only pill read as a long empty
    // bar).
    readonly property real contentWidth: leftRestRow.implicitWidth
        + restClock.requiredWidth + rightRestRow.implicitWidth
        + Config.island.restItemSpacing * 4

    RowLayout {
        id: leftRestRow
        anchors.right: restClock.left
        anchors.rightMargin: Config.island.restItemSpacing
        anchors.verticalCenter: parent.verticalCenter
        spacing: Config.island.restItemSpacing

        Repeater {
            model: root.leftDisplayOrder
            delegate: IslandRestItem {
                required property string modelData
                itemId: modelData
                Layout.preferredWidth: implicitWidth
                Layout.preferredHeight: implicitHeight
                onPowerHoveredChanged: if (itemId === "PowerProfile")
                    root.powerHovered = powerHovered
                onPowerRequested: root.powerRequested()
            }
        }
    }

    IslandRestItem {
        id: restClock
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        itemId: "Clock"
        // The real pill width, so the clock row lays out against it instead of
        // an estimate (an estimate overflowed the rounded ends by ~11px).
        availableWidth: root.width
        shareHosted: root.shareHosted
        workspaceSwitchActive: root.workspaceSwitchActive
        workspaceIndicatorMax: root.workspaceIndicatorMax
        previousWorkspaceId: root.previousWorkspaceId
        onCalendarRequested: root.calendarRequested()
        onDashboardRequested: root.dashboardRequested()
    }

    // Ink shared-element tag (island/SharedElements.qml): the rest clock is
    // measured here, and the shared clock is centred on it at 13/15.
    SharePoint {
        id: shareClock
        objectName: "share:clock"
        shareKind: "clock"
        shareState: "dormant"
        measure: restClock.clockMeasure ?? restClock
        shareLive: !root.workspaceSwitchActive
        shareScale: 13 / 15
    }
    readonly property var shareItems: [shareClock]

    RowLayout {
        id: rightRestRow
        anchors.left: restClock.right
        anchors.leftMargin: Config.island.restItemSpacing
        anchors.verticalCenter: parent.verticalCenter
        spacing: Config.island.restItemSpacing

        Repeater {
            model: root.rightDisplayOrder
            delegate: IslandRestItem {
                required property string modelData
                itemId: modelData
                Layout.preferredWidth: implicitWidth
                Layout.preferredHeight: implicitHeight
                onPowerHoveredChanged: if (itemId === "PowerProfile")
                    root.powerHovered = powerHovered
                onPowerRequested: root.powerRequested()
            }
        }

        // Unconditionally mounted (unlike the restItemOrder-gated items
        // above) -- own visibility is ScreenRecService.recording, same
        // "absent, not idling" contract as island/Eq.qml. Contributes 0
        // width while not recording.
        RecordingIndicator {
            Layout.preferredWidth: implicitWidth
            Layout.preferredHeight: implicitHeight
        }

        // Same contract as RecordingIndicator: 0 width unless the pomodoro
        // timer is running or paused.
        TimerIndicator {
            Layout.preferredWidth: implicitWidth
            Layout.preferredHeight: implicitHeight
            onPointerOverChanged: root.timerHovered = pointerOver
        }
    }
}
