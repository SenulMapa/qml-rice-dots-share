import QtQuick
import QtQuick.Layouts
import "../core"
import "../components"
import "../services"
import "../desktop/services" as Desk

Item {
    id: root

    // Ink (Config.appearance.ink): history grouped by app under a sentence-case
    // caption, sender avatars via NotificationAvatar, "Clear all" as a text
    // button, and a DND sentence under the title. No card fills.
    readonly property bool ink: Config.appearance.ink
    // Refreshed every 30s so the group times ("2m", "1h") age while open.
    property real nowMs: Date.now()

    Timer {
        running: root.ink && root.visible
        repeat: true
        interval: 30000
        onTriggered: root.nowMs = Date.now()
    }

    readonly property var groups: {
        const byApp = new Map()
        const out = []
        for (const entry of NotificationService.history) {
            const key = entry.appName || "Application"
            let group = byApp.get(key)
            if (!group) {
                group = { appName: key, latest: entry.timestamp, entries: [] }
                byApp.set(key, group)
                out.push(group)
            }
            group.entries.push(entry)
        }
        return out
    }

    function ageText(timestamp: real): string {
        const minutes = Math.floor((root.nowMs - timestamp) / 60000)
        if (minutes < 1)
            return "Now"
        if (minutes < 60)
            return minutes + "m"
        const hours = Math.floor(minutes / 60)
        return hours < 24 ? hours + "h" : Math.floor(hours / 24) + "d"
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.space1

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space1

            ColumnLayout {
                spacing: 0

                Text {
                    text: "Notifications"
                    color: root.ink ? Theme.t1 : AdaptiveColor.glassText
                    font.family: root.ink ? Theme.fontUi : Config.appearance.fontFamily
                    font.pixelSize: root.ink ? 20 : Theme.textBody
                    font.weight: Font.DemiBold
                }

                Text {
                    visible: !root.ink
                    text: NotificationService.count === 1
                        ? "1 recent item" : NotificationService.count + " recent items"
                    color: AdaptiveColor.glassTextDim
                    font.family: Config.appearance.fontFamily
                    font.pixelSize: 10
                }
            }

            Item { Layout.fillWidth: true }

            Text {
                visible: NotificationService.count > 0
                Layout.rightMargin: Theme.space2
                text: "Clear all"
                color: root.ink
                    ? (clearHover.hovered ? Theme.t2 : Theme.t1)
                    : clearHover.hovered ? Theme.error : AdaptiveColor.glassTextDim
                font.family: root.ink ? Theme.fontUi : Config.appearance.fontFamily
                font.pixelSize: root.ink ? 13 : 10
                font.weight: root.ink ? Font.DemiBold : Font.Medium

                HoverHandler { id: clearHover }
                TapHandler { onTapped: NotificationService.clearHistory() }
            }

            Rectangle {
                Layout.preferredWidth: dndContent.implicitWidth + Theme.space3 * 2
                Layout.preferredHeight: root.ink ? 32 : 30
                radius: root.ink ? height / 2 : Theme.radiusSmall
                color: root.ink
                    ? (NotificationService.doNotDisturb ? Theme.fillOn
                        : dndHover.hovered ? Theme.inkRaised2 : Theme.inkRaised)
                    : dndHover.hovered
                    ? (NotificationService.doNotDisturb
                        ? Theme.primaryContainer : Theme.surfaceContainerHigh)
                    : "transparent"
                border.width: !root.ink && dndHover.hovered ? 1 : 0
                border.color: Qt.alpha(Theme.outlineVariant, 0.54)

                RowLayout {
                    id: dndContent
                    anchors.centerIn: parent
                    spacing: Theme.space1

                    Text {
                        text: NotificationService.doNotDisturb ? "󰂛" : "󰂚"
                        color: root.ink
                            ? (NotificationService.doNotDisturb ? Theme.glyphOn : Theme.t1)
                            : AdaptiveColor.glassText
                        font.family: Config.appearance.monoFontFamily
                        font.pixelSize: Theme.iconSmall
                    }

                    Text {
                        text: NotificationService.doNotDisturb ? "DND on" : "DND off"
                        // DND state is communicated by the bell; keep the label
                        // legible and stable across dark/light palettes.
                        color: root.ink
                            ? (NotificationService.doNotDisturb ? Theme.glyphOn : Theme.t1)
                            : AdaptiveColor.glassText
                        font.family: root.ink ? Theme.fontUi : Config.appearance.fontFamily
                        font.pixelSize: root.ink ? 12 : 10
                        font.weight: Font.Medium
                    }
                }

                HoverHandler { id: dndHover }
                TapHandler { onTapped: NotificationService.toggleDoNotDisturb() }
                Behavior on color { ColorAnimation { duration: Animations.fast } }
            }
        }

        // Ink: one sentence under the title, Geist 13/500 t2.
        Text {
            visible: root.ink
            Layout.fillWidth: true
            text: NotificationService.doNotDisturb
                ? "Do not disturb is on. New notifications stay quiet."
                : "Do not disturb is off. Popups show as they arrive."
            color: Theme.t2
            wrapMode: Text.WordWrap
            font.family: Theme.fontUi
            font.pixelSize: 13
            font.weight: Font.Medium
        }

        // Ink: grouped by app. Each group is a 12/500 t3 caption (app name,
        // newest age on the right) above its rows, with whitespace between.
        ListView {
            id: inkList
            visible: root.ink
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 0
            model: root.groups

            delegate: Column {
                id: groupColumn
                required property var modelData
                width: parent.width

                Item {
                    width: parent.width
                    height: 38

                    RowLayout {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 4
                        anchors.rightMargin: 4
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 6

                        Text {
                            Layout.fillWidth: true
                            text: groupColumn.modelData.appName
                            color: Theme.t3
                            elide: Text.ElideRight
                            font.family: Theme.fontUi
                            font.pixelSize: 12
                            font.weight: Font.Medium
                        }

                        Text {
                            text: root.ageText(groupColumn.modelData.latest)
                            color: Theme.t3
                            font.family: Theme.fontUi
                            font.pixelSize: 12
                            font.weight: Font.Medium
                        }

                        Text {
                            Layout.leftMargin: 12
                            text: "Clear"
                            color: groupClearHover.hovered ? Theme.t1 : Theme.t3
                            font.family: Theme.fontUi
                            font.pixelSize: 12
                            font.weight: Font.Medium

                            HoverHandler { id: groupClearHover }
                            TapHandler { onTapped: NotificationService.clearApp(groupColumn.modelData.appName) }
                        }
                    }
                }

                Repeater {
                    model: groupColumn.modelData.entries

                    delegate: Item {
                        id: inkRow
                        required property var modelData
                        required property int index
                        width: parent.width
                        implicitHeight: inkBody.implicitHeight + 20
                        height: implicitHeight
                        readonly property bool hasPrimary: NotificationService.canActivate(modelData)
                            || NotificationService.visibleActions(modelData).length > 0

                        NotificationAvatar {
                            id: inkAvatar
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.top: parent.top
                            anchors.topMargin: 10
                            entry: inkRow.modelData
                            size: 40
                        }

                        ColumnLayout {
                            id: inkBody
                            anchors.left: inkAvatar.right
                            anchors.leftMargin: 14
                            anchors.right: inkDismiss.left
                            anchors.rightMargin: 8
                            anchors.top: parent.top
                            anchors.topMargin: 10
                            spacing: 0

                            Text {
                                Layout.fillWidth: true
                                text: inkRow.modelData.title || "Notification"
                                color: Theme.t1
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                font.family: Theme.fontUi
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: (inkRow.modelData.body || "").length > 0
                                text: inkRow.modelData.body || ""
                                color: Theme.t2
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                font.family: Theme.fontUi
                                font.pixelSize: 13
                                font.weight: Font.Medium
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: 8
                                visible: NotificationService.visibleActions(inkRow.modelData).length > 0
                                spacing: 18

                                Repeater {
                                    model: NotificationService.visibleActions(inkRow.modelData)
                                    delegate: Text {
                                        required property var modelData
                                        required property int index
                                        text: NotificationService.plainText(modelData?.text || "")
                                        color: inkLinkHover.hovered ? Theme.t2 : Theme.t1
                                        font.family: Theme.fontUi
                                        font.pixelSize: 13
                                        font.weight: Font.DemiBold

                                        HoverHandler { id: inkLinkHover }
                                        TapHandler { onTapped: NotificationService.invokeAction(inkRow.modelData, index) }
                                    }
                                }

                                Item { Layout.fillWidth: true }
                            }
                        }

                        Text {
                            id: inkDismiss
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.top: parent.top
                            anchors.topMargin: 6
                            text: "×"
                            color: inkDismissHover.hovered ? Theme.t1 : Theme.t3
                            font.family: Theme.fontUi
                            font.pixelSize: 18

                            HoverHandler { id: inkDismissHover }
                            TapHandler { onTapped: NotificationService.remove(inkRow.modelData) }
                        }

                        TapHandler {
                            enabled: inkRow.hasPrimary
                            onTapped: {
                                if (NotificationService.canActivate(inkRow.modelData))
                                    NotificationService.activate(inkRow.modelData)
                                else
                                    NotificationService.invokeAction(inkRow.modelData, 0)
                            }
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: NotificationService.count === 0
                text: NotificationService.doNotDisturb
                    ? "Quiet mode is active" : "All quiet"
                color: Theme.t3
                font.family: Theme.fontUi
                font.pixelSize: 14
            }
        }

        // Ink: a one-line status strip under the list. It reads the same
        // sources as the dashboard: weather, tasks due today, and the iPhone
        // battery when the phone is enabled.
        RowLayout {
            id: statusRow
            visible: root.ink
            Layout.fillWidth: true
            spacing: 18

            readonly property int tasksToday: Desk.DeskTasksService.pendingOn(Desk.DeskTasksService.todayKey)
            readonly property var nextTask: Desk.DeskTasksService.next

            RowLayout {
                visible: WeatherService.available
                spacing: 6

                Text {
                    text: WeatherService.icon
                    color: Theme.t2
                    font.family: Config.appearance.monoFontFamily
                    font.pixelSize: Theme.iconSmall
                }

                Text {
                    text: WeatherService.temperatureLabel
                    color: Theme.t2
                    font.family: Theme.fontUi
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
            }

            Text {
                Layout.fillWidth: true
                text: statusRow.tasksToday > 0
                    ? statusRow.tasksToday + (statusRow.tasksToday === 1 ? " task" : " tasks") + " due today"
                    : statusRow.nextTask ? "Next: " + statusRow.nextTask.text : "No tasks due"
                color: Theme.t2
                elide: Text.ElideRight
                font.family: Theme.fontUi
                font.pixelSize: 13
                font.weight: Font.Medium
            }

            Text {
                visible: Config.phone.enabled
                text: PhoneService.connected && PhoneService.status
                    ? "iPhone " + PhoneService.status.battery + "%" : "iPhone offline"
                color: Theme.t2
                font.family: Theme.fontUi
                font.pixelSize: 13
                font.weight: Font.Medium
            }
        }

        ListView {
            id: historyList
            visible: !root.ink
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Theme.space1
            model: NotificationService.history

            delegate: NotificationCard {
                required property var modelData
                width: historyList.width
                entry: modelData
            }

            Text {
                anchors.centerIn: parent
                visible: NotificationService.count === 0
                text: NotificationService.doNotDisturb
                    ? "Quiet mode is active" : "All quiet"
                color: AdaptiveColor.glassTextDim
                font.family: Config.appearance.fontFamily
                font.pixelSize: Theme.textBody
            }
        }
    }
}
