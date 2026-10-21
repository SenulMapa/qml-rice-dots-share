import QtQuick
import QtQuick.Layouts
import "../core"
import "../components"
import "../services"
import "../desktop/services" as Desk

/**
 * MacNotificationColumn -- the content of the Notification Center (spec 3.3):
 * the notifications grouped by app, then the widgets. It has no window of its
 * own, so the render harness can host it directly. The window and the
 * open/close state live in MacNotificationCenter.qml.
 *
 * The sources are properties with the live services as defaults, so the
 * render harness can pass fixtures with the same members.
 */
Item {
    id: root

    property var notifications: NotificationService.history
    property var weather: WeatherService
    property var tasks: Desk.DeskTasksService
    property var todo: TodoService
    property var phone: PhoneService
    property var media: MediaService
    property real nowMs: Date.now()
    property string weatherCity: Config.weather.locationName
    // 0 = off the right edge, 1 = open. Driven by MacNotificationCenter.
    property real shown: 1

    readonly property real pad: MacTokens.s(MacTokens.bannerPad)
    readonly property real columnWidth: MacTokens.s(MacTokens.ncColumnWidth)
    readonly property real screenInset: MacTokens.s(MacTokens.ncInsetRight)
    readonly property real hoverRoom: MacTokens.s(MacTokens.ncHoverRoom)
    readonly property real slide: root.columnWidth + root.pad + root.screenInset
    readonly property real windowWidth: root.pad + root.columnWidth + root.screenInset
    // Input region of the layer: the column only, from its top inset down, so
    // the menu bar above it stays clickable.
    readonly property alias region: hitRegion

    signal closeRequested()

    // The New Message sheet is open (MacCompose).
    property bool composing: false

    // Spotlight "message <name>" sets PhoneService.composeTarget: open the sheet
    // on that recipient, then clear the request so it is taken once.
    function takeComposeTarget(): void {
        const target = root.phone?.composeTarget
        if (!target)
            return
        root.composing = true
        compose.setRecipient(target)
        root.phone.clearCompose()
    }

    Connections {
        target: root.phone
        function onComposeTargetChanged(): void { root.takeComposeTarget() }
    }

    Component.onCompleted: root.takeComposeTarget()

    implicitWidth: root.windowWidth

    Keys.onEscapePressed: root.closeRequested()

    Timer {
        interval: 30000
        running: root.visible
        repeat: true
        onTriggered: root.nowMs = Date.now()
    }

    readonly property var groups: {
        const byApp = new Map()
        const out = []
        for (const entry of (root.notifications ?? [])) {
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

    // Long lists stay readable at 1080p: the latest groups show, two cards each,
    // with "+N more" expanders. Widgets stay in view below them.
    property int groupLimit: 4
    property int cardLimit: 2
    property bool showAllGroups: false
    readonly property var visibleGroups: root.showAllGroups ? root.groups : root.groups.slice(0, root.groupLimit)
    readonly property int hiddenGroupCount: root.groups.length - root.visibleGroups.length

    readonly property var todayTasks: root.tasks.on(root.tasks.todayKey)
    readonly property var openReminders: (root.todo?.items ?? []).filter(item => !item.done)

    // Hit region of the layer (see MacNcWindow): the column from its top inset down.
    Item {
        id: hitRegion
        x: flick.x
        y: MacTokens.s(MacTokens.ncTopInset)
        width: flick.width
        height: root.height - y
    }

    Flickable {
        id: flick
        // Starts hoverRoom left of the cards: the hover close circles hang past the card's left edge.
        x: root.pad - root.hoverRoom + (1 - root.shown) * root.slide
        y: 0
        width: root.columnWidth + root.hoverRoom
        height: root.height
        contentWidth: width
        contentHeight: stack.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: stack
            x: root.hoverRoom
            width: root.columnWidth
            topPadding: MacTokens.s(MacTokens.ncTopInset)

            // Top row: Clear All. It is an ink pill that shows while the column is hovered.
            Item {
                width: stack.width
                height: MacTokens.s(MacTokens.ncClearAllHeight) + MacTokens.s(MacTokens.ncClearAllGap)

                MacInkPill {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    text: "Clear All"
                    heightPt: MacTokens.ncClearAllHeight
                    textPt: MacTokens.ncClearAllTextSize
                    opacity: columnHover.hovered ? 1 : 0
                    enabled: columnHover.hovered
                    onTapped: NotificationService.clearHistory()
                }
                // Opens the New Message sheet (iPhone messages from this desktop).
                MacInkPill {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    visible: Config.phone.enabled && !root.composing
                    text: "New Message"
                    heightPt: MacTokens.ncClearAllHeight
                    textPt: MacTokens.ncClearAllTextSize
                    onTapped: {
                        root.composing = true
                        compose.reset()
                    }
                }
            }

            // The New Message sheet sits above the notifications while open.
            MacCompose {
                id: compose
                width: stack.width
                visible: root.composing
                phone: root.phone
                onCloseRequested: root.composing = false
            }

            Item {
                width: stack.width
                visible: root.composing
                height: MacTokens.s(MacTokens.ncWidgetGap)
            }

            Repeater {
                model: root.visibleGroups

                // One app group. Collapsed (default): the newest card in full, with
                // two back layers showing below it, like the macOS stack. Expanded:
                // every card, 8 pt apart. The gap to the next group is 14 pt.
                delegate: Column {
                    id: groupColumn
                    required property var modelData
                    readonly property int count: modelData.entries.length
                    readonly property bool canExpand: count > 1
                    property bool expanded: false
                    readonly property real peek: MacTokens.s(MacTokens.ncPeekStep)
                    readonly property real cardGap: MacTokens.s(MacTokens.ncExpandedGap)
                    readonly property real cardRadius: MacTokens.s(MacTokens.ncCardRadius)
                    width: stack.width
                    // Clean gap to the next group (owner spec).
                    bottomPadding: MacTokens.s(MacTokens.ncWidgetGap)

                    // One box holds the stack, so the cards overlap the back layers
                    // instead of being laid out after them. Back layers are declared
                    // first (drawn below the cards). The pills come last (drawn above).
                    Item {
                        id: stackBox
                        width: groupColumn.width
                        readonly property bool collapsed: !groupColumn.expanded
                        height: groupColumn.expanded && groupColumn.count > 1
                            ? expandedCards.height
                            : topCard.height + (groupColumn.canExpand ? groupColumn.peek * 2 : 0)

                        HoverHandler { id: groupHover }

                        // Back layers: each one shows 6 pt more below the card in front.
                        // Both are 2 radii tall, so their rounded bottoms stay true.
                        Squircle {
                            visible: stackBox.collapsed && groupColumn.canExpand
                            x: MacTokens.s(MacTokens.ncPeekInset2)
                            width: stackBox.width - 2 * x
                            y: topCard.height + groupColumn.peek * 2 - height
                            height: 2 * groupColumn.cardRadius
                            radius: groupColumn.cardRadius
                            color: MacTokens.ncPeekFillBack
                        }
                        Squircle {
                            visible: stackBox.collapsed && groupColumn.canExpand
                            x: MacTokens.s(MacTokens.ncPeekInset1)
                            width: stackBox.width - 2 * x
                            y: topCard.height + groupColumn.peek - height
                            height: 2 * groupColumn.cardRadius
                            radius: groupColumn.cardRadius
                            color: MacTokens.ncPeekFill
                        }

                        // Collapsed stack: a tap anywhere on it expands it (no "+N more"
                        // label, macOS has none). The top card does not activate then.
                        TapHandler {
                            enabled: groupColumn.canExpand && stackBox.collapsed
                            onTapped: groupColumn.expanded = true
                        }

                        MacNotificationCard {
                            id: topCard
                            width: stackBox.width
                            entry: groupColumn.modelData.entries[0]
                            nowMs: root.nowMs
                            visible: stackBox.collapsed || groupColumn.count === 1
                            activatable: !groupColumn.canExpand
                            headerInset: pillRow.visible ? pillRow.width + MacTokens.s(MacTokens.ncPillGap) : 0
                        }

                        Column {
                            id: expandedCards
                            width: stackBox.width
                            spacing: groupColumn.cardGap
                            visible: !stackBox.collapsed && groupColumn.count > 1

                            Repeater {
                                model: groupColumn.expanded ? groupColumn.modelData.entries : []

                                delegate: MacNotificationCard {
                                    required property var modelData
                                    required property int index
                                    width: stackBox.width
                                    entry: modelData
                                    nowMs: root.nowMs
                                    headerInset: index === 0 && pillRow.visible
                                        ? pillRow.width + MacTokens.s(MacTokens.ncPillGap) : 0
                                }
                            }
                        }

                        // Group pills: Clear, and Show less while expanded. They show while
                        // the group is hovered or expanded, over the top card's top right.
                        Row {
                            id: pillRow
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.topMargin: MacTokens.s(MacTokens.ncGroupPillInset)
                            anchors.rightMargin: MacTokens.s(MacTokens.ncCardPadX)
                            spacing: MacTokens.s(MacTokens.ncPillGap)
                            visible: groupHover.hovered || groupColumn.expanded
                            z: 1

                            MacInkPill {
                                text: "Clear"
                                onTapped: NotificationService.clearApp(groupColumn.modelData.appName)
                            }

                            MacInkPill {
                                visible: groupColumn.expanded && groupColumn.canExpand
                                text: "Show less"
                                onTapped: groupColumn.expanded = false
                            }
                        }
                    }
                }
            }

            // "Show N more" pill, centred under the groups. Its own bottom gap is the
            // 14 pt before the widgets.
            Item {
                width: stack.width
                visible: root.hiddenGroupCount > 0 || (root.showAllGroups && root.groups.length > root.groupLimit)
                height: visible ? MacTokens.s(MacTokens.ncShowMoreHeight) + MacTokens.s(MacTokens.ncWidgetGap) : 0

                MacInkPill {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    text: root.showAllGroups ? "Show fewer" : "Show " + root.hiddenGroupCount + " more"
                    heightPt: MacTokens.ncShowMoreHeight
                    textPt: MacTokens.ncShowMoreTextSize
                    onTapped: root.showAllGroups = !root.showAllGroups
                }
            }

            Text {
                width: stack.width
                visible: root.groups.length === 0
                horizontalAlignment: Text.AlignHCenter
                bottomPadding: MacTokens.s(MacTokens.ncWidgetGap)
                text: NotificationService.doNotDisturb ? "Quiet mode is active" : "No notifications"
                color: MacTokens.onGlassHeader
                style: Text.Raised
                styleColor: MacTokens.onGlassShadow
                font.family: MacTokens.textFamily
                font.pixelSize: MacTokens.s(MacTokens.ncGroupLabelSize)
            }

            // Widgets: 14 pt apart, the same width as the cards. A list with nothing
            // to show is left out entirely (Column skips hidden children).
            Column {
                width: stack.width
                spacing: MacTokens.s(MacTokens.ncWidgetGap)

                MacWidgetWeather {
                    visible: root.weather.configured
                    weather: root.weather
                    city: root.weatherCity
                }

                MacWidgetList {
                    visible: root.todayTasks.length > 0
                    label: "Today"
                    glyph: "󰃭"
                    count: root.tasks.pendingOn(root.tasks.todayKey)
                    rows: root.todayTasks.map(task => ({ text: task.text }))
                }

                MacWidgetList {
                    visible: root.openReminders.length > 0
                    label: "Reminders"
                    glyph: "󰄬"
                    count: root.openReminders.length
                    rows: root.openReminders.map(item => ({ text: item.text }))
                }

                MacWidgetBattery {
                    visible: Config.phone.enabled
                    phone: root.phone
                }

                MacWidgetNowPlaying {
                    visible: root.media.available
                    media: root.media
                }
            }

            // 16 pt bottom padding below the last widget (owner: spacing at the edges).
            Item { width: stack.width; height: MacTokens.s(MacTokens.ncBottomPad) }
        }
    }

    // Hover over the column shows Clear All. Declared last so it sees the whole column.
    HoverHandler { id: columnHover; target: flick }
}
