import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"
import "../components"

Item {
    id: root

    property date displayedMonth: new Date(ShellState.now.getFullYear(),
        ShellState.now.getMonth(), 1)
    property date selectedDate: new Date(ShellState.now.getFullYear(),
        ShellState.now.getMonth(), ShellState.now.getDate())
    // Future calendar providers can populate this without changing the month UI.
    property var events: []
    readonly property var weekdayLabels: ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
    readonly property var monthCells: buildMonthCells()

    function sameDay(first, second): bool {
        return first.getFullYear() === second.getFullYear()
            && first.getMonth() === second.getMonth()
            && first.getDate() === second.getDate()
    }

    function buildMonthCells(): var {
        const year = displayedMonth.getFullYear()
        const month = displayedMonth.getMonth()
        const firstWeekday = new Date(year, month, 1).getDay()
        const cells = []
        for (let index = 0; index < 42; index++) {
            const date = new Date(year, month, index - firstWeekday + 1)
            cells.push({
                date: date,
                day: date.getDate(),
                inMonth: date.getMonth() === month,
                today: sameDay(date, ShellState.now),
                selected: sameDay(date, selectedDate)
            })
        }
        return cells
    }

    function changeMonth(offset): void {
        displayedMonth = new Date(displayedMonth.getFullYear(),
            displayedMonth.getMonth() + offset, 1)
    }

    function returnToToday(): void {
        selectedDate = new Date(ShellState.now.getFullYear(),
            ShellState.now.getMonth(), ShellState.now.getDate())
        displayedMonth = new Date(ShellState.now.getFullYear(),
            ShellState.now.getMonth(), 1)
    }

    RowLayout {
        anchors.fill: parent
        spacing: Theme.space3

        Item {
            Layout.preferredWidth: 188
            Layout.fillHeight: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.space4
                spacing: Theme.space2

                Text {
                    text: Qt.formatDate(root.selectedDate, "dddd").toUpperCase()
                    color: AdaptiveColor.activeFill
                    font.family: Config.appearance.monoFontFamily
                    font.pixelSize: 9
                    font.letterSpacing: 1.1
                    font.weight: Font.DemiBold
                }
                Text {
                    text: Qt.formatDate(root.selectedDate, "d")
                    color: AdaptiveColor.glassText
                    font.family: Config.appearance.monoFontFamily
                    font.pixelSize: 54
                    font.weight: Font.DemiBold
                }
                Text {
                    text: Qt.formatDate(root.selectedDate, "MMMM yyyy")
                    color: AdaptiveColor.glassTextDim
                    font.family: Config.appearance.fontFamily
                    font.pixelSize: 12
                    font.weight: Font.Medium
                }

                Item { Layout.preferredHeight: Theme.space2 }

                Text {
                    text: "SCHEDULE"
                    color: AdaptiveColor.glassTextDim
                    font.family: Config.appearance.monoFontFamily
                    font.pixelSize: 8
                    font.letterSpacing: 1
                }
                Text {
                    Layout.fillWidth: true
                    text: root.events.length > 0
                        ? root.events.length + " events" : "Nothing scheduled"
                    color: AdaptiveColor.glassText
                    wrapMode: Text.WordWrap
                    font.family: Config.appearance.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
                Text {
                    Layout.fillWidth: true
                    text: "Calendar providers will appear here when connected."
                    color: AdaptiveColor.glassTextDim
                    wrapMode: Text.WordWrap
                    font.family: Config.appearance.fontFamily
                    font.pixelSize: 9
                }

                Item { Layout.fillHeight: true }

                Squircle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    radius: Theme.radiusSmall
                    color: todayHover.hovered ? Theme.primaryContainer
                        : Theme.surfaceContainerHigh
                    Text {
                        anchors.centerIn: parent
                        text: "Return to today"
                        color: todayHover.hovered ? Theme.primaryContainerText
                            : AdaptiveColor.glassText
                        font.family: Config.appearance.fontFamily
                        font.pixelSize: 9
                        font.weight: Font.DemiBold
                    }
                    HoverHandler { id: todayHover }
                    TapHandler { onTapped: root.returnToToday() }
                    Behavior on color { ColorAnimation { duration: Animations.fast } }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.space4
                spacing: Theme.space2

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30

                    Text {
                        Layout.fillWidth: true
                        text: Qt.formatDate(root.displayedMonth, "MMMM yyyy")
                        color: AdaptiveColor.glassText
                        font.family: Config.appearance.displayFontFamily
                        font.pixelSize: Theme.textTitle + 6
                        font.weight: Font.Normal
                    }
                    Repeater {
                        model: [
                            { icon: "‹", offset: -1 },
                            { icon: "›", offset: 1 }
                        ]
                        delegate: Squircle {
                            required property var modelData
                            Layout.preferredWidth: 30
                            Layout.preferredHeight: 30
                            radius: Theme.radiusSmall
                            color: monthHover.hovered
                                ? Theme.surfaceContainerHigh : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: modelData.icon
                                color: AdaptiveColor.glassTextDim
                                // The UI text font (Config.appearance.
                                // fontFamily) doesn't cover U+2039/U+203A
                                // (angle quotation marks) in this
                                // environment and falls back to something
                                // that reads as plain parentheses -- the
                                // icon font (used for every glyph
                                // elsewhere in this shell) does.
                                font.family: Config.appearance.monoFontFamily
                                font.pixelSize: 18
                            }
                            HoverHandler { id: monthHover }
                            TapHandler { onTapped: root.changeMonthSlide(modelData.offset) }
                        }
                    }
                }

                GridLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 18
                    columns: 7
                    columnSpacing: 4
                    Repeater {
                        model: root.weekdayLabels
                        delegate: Text {
                            required property string modelData
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData
                            color: AdaptiveColor.glassTextDim
                            font.family: Config.appearance.monoFontFamily
                            font.pixelSize: 7
                            font.weight: Font.DemiBold
                        }
                    }
                }

                // Slides + fades in on a month change -- wrapped in a plain
                // Item so the GridLayout inside can carry a transform/
                // opacity without disturbing the outer ColumnLayout cell.
                // Same replay-from-a-displaced-state idiom components/
                // Reveal.qml uses (a spring has no notion of "jump to an
                // offset and settle" -- see core/MotionValue.qml's own
                // leaf-signal contract -- so this is a plain NumberAnimation
                // pair, deliberately not a spring).
                Item {
                    id: monthGridWrap
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    GridLayout {
                        id: monthGrid
                        anchors.fill: parent
                        columns: 7
                        rows: 6
                        columnSpacing: 4
                        rowSpacing: 4
                        transform: Translate { id: monthSlide; x: 0 }

                        Repeater {
                            model: root.monthCells
                            delegate: Squircle {
                                id: dayCell
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: Theme.radiusSmall
                                // Selected fill is state, not decoration --
                                // it's the only way to read the grid. Today
                                // is a small dot under the number instead of
                                // a filled wash, so it reads as a marker,
                                // not a second kind of selection.
                                color: modelData.selected ? AdaptiveColor.activeFill
                                    : dayHover.hovered
                                        ? Qt.alpha(AdaptiveColor.glassText, 0.05)
                                        : "transparent"
                                borderWidth: 0

                                Text {
                                    id: dayNumber
                                    anchors.centerIn: parent
                                    anchors.verticalCenterOffset: -2
                                    text: modelData.day
                                    color: modelData.selected ? AdaptiveColor.activeFillText
                                        : modelData.inMonth ? AdaptiveColor.glassText
                                        : Qt.alpha(AdaptiveColor.glassTextDim, 0.38)
                                    font.family: Config.appearance.monoFontFamily
                                    font.pixelSize: 9
                                    font.weight: modelData.today || modelData.selected
                                        ? Font.Bold : Font.Normal
                                }
                                Rectangle {
                                    visible: modelData.today && !modelData.selected
                                    anchors.horizontalCenter: dayNumber.horizontalCenter
                                    anchors.top: dayNumber.bottom
                                    anchors.topMargin: 2
                                    width: 3; height: 3
                                    radius: 1.5
                                    color: AdaptiveColor.activeFill
                                }
                                HoverHandler { id: dayHover }
                                TapHandler {
                                    onTapped: {
                                        root.selectedDate = dayCell.modelData.date
                                        if (!dayCell.modelData.inMonth)
                                            root.displayedMonth = new Date(
                                                dayCell.modelData.date.getFullYear(),
                                                dayCell.modelData.date.getMonth(), 1)
                                    }
                                }
                                Behavior on color {
                                    ColorAnimation { duration: Animations.fast }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    property int monthSlideDir: 1

    function changeMonthSlide(offset): void {
        root.monthSlideDir = offset >= 0 ? 1 : -1
        root.changeMonth(offset)
    }

    onDisplayedMonthChanged: {
        monthSlideAnim.stop()
        monthFadeAnim.stop()
        monthSlide.x = root.monthSlideDir * 22
        monthGrid.opacity = 0.3
        monthSlideAnim.restart()
        monthFadeAnim.restart()
    }

    NumberAnimation {
        id: monthSlideAnim
        target: monthSlide
        property: "x"
        to: 0
        duration: Animations.normal
        easing.type: Animations.emphasizedEase
    }
    NumberAnimation {
        id: monthFadeAnim
        target: monthGrid
        property: "opacity"
        to: 1
        duration: Animations.normal
        easing.type: Animations.emphasizedEase
    }
}
