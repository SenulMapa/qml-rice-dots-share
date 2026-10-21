import QtQuick
import QtQuick.Layouts
import "../core"
import "../components"
import "../services"

Item {
    id: root
    property string query: ""
    property string copiedEntryId: ""
    property int currentIndex: -1
    property ArmState clearArm: ArmState { }
    readonly property var filteredEntries: ClipboardService.entries.filter(entry =>
        !query || (entry.kind === "text" ? entry.preview : entry.search)
            .toLowerCase().indexOf(query.toLowerCase()) >= 0)

    function resetSelection(): void {
        currentIndex = filteredEntries.length > 0 ? 0 : -1
        if (currentIndex >= 0)
            historyList.positionViewAtIndex(currentIndex, ListView.Contain)
    }

    function moveSelection(delta: int): void {
        if (filteredEntries.length === 0)
            return
        currentIndex = (Math.max(0, currentIndex) + delta
            + filteredEntries.length) % filteredEntries.length
    }

    function restoreSelection(): void {
        if (currentIndex >= 0 && currentIndex < filteredEntries.length)
            ClipboardService.copy(filteredEntries[currentIndex].id)
    }

    function removeSelection(): void {
        if (currentIndex >= 0 && currentIndex < filteredEntries.length)
            ClipboardService.remove(filteredEntries[currentIndex].id)
    }

    // "Clear all" arms in place instead of opening a bordered confirmation
    // alert -- same components/ArmState.qml machine panels/SessionPage.qml
    // uses for its tiles.
    function performClear(): void {
        if (!clearArm.press("clear-all", true))
            return
        ClipboardService.clearHistory()
    }

    onFilteredEntriesChanged: resetSelection()
    onVisibleChanged: {
        if (visible) {
            clearArm.disarm()
            ClipboardService.beginPresentation()
            ClipboardService.refresh()
            Qt.callLater(() => searchField.forceActiveFocus())
        } else ClipboardService.endPresentation()
    }

    Connections {
        target: ClipboardService
        function onCopied(entryId): void {
            root.copiedEntryId = entryId
            copiedFeedback.restart()
        }
        function onCleared(): void {
            root.clearArm.disarm()
            root.currentIndex = -1
        }
    }
    Timer {
        id: copiedFeedback
        interval: 900
        onTriggered: root.copiedEntryId = ""
    }
    // ArmState owns no QML Timer itself -- this is the tick that expires the
    // "Clear all" arm after 3000ms of silence (see components/ArmState.qml).
    Timer {
        interval: 150
        repeat: true
        running: root.clearArm.hasArmed
        onTriggered: root.clearArm.checkExpiry()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.space3

        RowLayout {
            Layout.fillWidth: true
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    text: "Clipboard"
                    color: (Config.appearance.ink ? Theme.t1 : AdaptiveColor.glassText)
                    font.family: Config.appearance.ink ? Theme.fontUi : Config.appearance.displayFontFamily
                    font.pixelSize: Config.appearance.ink ? 20 : Theme.textTitle + 6
                    font.weight: Config.appearance.ink ? Font.DemiBold : Font.Normal
                }
                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        text: root.filteredEntries.length + " history entries"
                        color: (Config.appearance.ink ? Theme.t2 : AdaptiveColor.glassTextDim)
                        font.family: (Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily)
                        font.pixelSize: Theme.textSmall
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: "󰑐  Refresh"
                        color: refreshHover.hovered ? (Config.appearance.ink ? Theme.t1 : AdaptiveColor.activeFill) : (Config.appearance.ink ? Theme.t2 : AdaptiveColor.glassTextDim)
                        font.family: (Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily)
                        font.pixelSize: Theme.textSmall
                        HoverHandler { id: refreshHover }
                        TapHandler { onTapped: ClipboardService.refresh() }
                    }
                    Text {
                        visible: ClipboardService.entries.length > 0
                        text: root.clearArm.isArmed("clear-all") ? "Confirm" : "󰆴  Clear"
                        color: root.clearArm.isArmed("clear-all") ? Theme.error
                            : clearHover.hovered ? Theme.error : (Config.appearance.ink ? Theme.t2 : AdaptiveColor.glassTextDim)
                        font.family: (Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily)
                        font.pixelSize: Theme.textSmall
                        font.weight: root.clearArm.isArmed("clear-all")
                            ? Font.DemiBold : Font.Normal
                        HoverHandler { id: clearHover }
                        TapHandler { onTapped: root.performClear() }
                    }
                }
            }
        }

        // Current selection -- unboxed. No border, no card fill; the launcher
        // row language elsewhere on this page is a good enough visual anchor
        // that this doesn't need its own container.
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space3

            Rectangle {
                visible: ClipboardService.currentKind === "image"
                Layout.preferredWidth: visible ? Theme.u(1.22) : 0
                Layout.preferredHeight: visible ? Theme.u(1.0) : 0
                radius: Theme.u(0.17)
                clip: true
                color: Config.appearance.ink ? Theme.inkRaised : Theme.surfaceContainer
                Image {
                    anchors.fill: parent
                    source: ClipboardService.thumbnailSource("current")
                    asynchronous: true
                    cache: false
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: Config.clipboard.thumbnailWidth
                    sourceSize.height: Config.clipboard.thumbnailHeight
                }
            }
            Text {
                visible: ClipboardService.currentKind !== "image"
                text: ClipboardService.currentKind === "text" ? "󰅌" : "󰋩"
                color: (Config.appearance.ink ? Theme.t1 : AdaptiveColor.activeFill)
                font.family: Config.appearance.monoFontFamily
                font.pixelSize: Theme.textBody + 2
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    text: "Current selection"
                    color: (Config.appearance.ink ? Theme.t2 : AdaptiveColor.glassTextDim)
                    font.family: (Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily)
                    font.pixelSize: Theme.textSmall
                }
                Text {
                    Layout.fillWidth: true
                    text: ClipboardService.currentKind === "text" ? ClipboardService.currentPreview
                        : ClipboardService.currentKind === "image" ? "Image · " + ClipboardService.currentImageFormat
                        : ClipboardService.currentKind === "checking" ? "Checking current selection…"
                        : ClipboardService.currentKind === "unsupported" ? "Image or binary data cannot be previewed"
                        : "Clipboard is empty or unavailable"
                    color: (Config.appearance.ink ? Theme.t1 : AdaptiveColor.glassText)
                    font.family: (Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily)
                    font.pixelSize: Theme.textBody
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }
        }

        Squircle {
            Layout.fillWidth: true
            Layout.preferredHeight: Config.appearance.ink ? 44 : Theme.u(1.39)
            radius: Config.appearance.ink ? Theme.rCtl : Theme.u(0.23)
            color: Config.appearance.ink ? Theme.inkRaised : Theme.surfaceContainerHigh
            RowLayout {
                anchors.fill: parent
                anchors.margins: Config.appearance.ink ? 14 : Theme.space3
                Text { text: "󰍉"; color: (Config.appearance.ink ? Theme.t3 : AdaptiveColor.activeFill); font.family: Config.appearance.monoFontFamily }
                TextInput {
                    id: searchField
                    Layout.fillWidth: true
                    text: root.query
                    onTextChanged: root.query = text
                    color: (Config.appearance.ink ? Theme.t1 : AdaptiveColor.glassText)
                    selectionColor: Theme.primaryContainer
                    selectedTextColor: Theme.primaryContainerText
                    font.family: (Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily)
                    font.pixelSize: Theme.textBody
                    clip: true
                    selectByMouse: true
                    verticalAlignment: TextInput.AlignVCenter
                    Text {
                        anchors.fill: parent
                        visible: !searchField.text
                        text: Config.appearance.ink ? "Search clipboard" : "Search local clipboard history"
                        color: (Config.appearance.ink ? Theme.t3 : AdaptiveColor.glassTextDim)
                        verticalAlignment: Text.AlignVCenter
                        font: searchField.font
                    }

                    Keys.onPressed: event => {
                        if (root.clearArm.hasArmed) {
                            if (event.key === Qt.Key_Escape) {
                                root.clearArm.disarm()
                                event.accepted = true
                            } else if (event.key === Qt.Key_Return
                                    || event.key === Qt.Key_Enter) {
                                root.performClear()
                                event.accepted = true
                            }
                            return
                        }

                        if (event.key === Qt.Key_Down) {
                            root.moveSelection(1)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Up) {
                            root.moveSelection(-1)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Home) {
                            root.currentIndex = root.filteredEntries.length > 0 ? 0 : -1
                            historyList.positionViewAtBeginning()
                            event.accepted = true
                        } else if (event.key === Qt.Key_End) {
                            root.currentIndex = root.filteredEntries.length - 1
                            historyList.positionViewAtEnd()
                            event.accepted = true
                        } else if (event.key === Qt.Key_Return
                                || event.key === Qt.Key_Enter) {
                            root.restoreSelection()
                            event.accepted = true
                        } else if (event.key === Qt.Key_Delete
                                && (searchField.text.length === 0
                                    || (event.modifiers & Qt.ControlModifier))) {
                            root.removeSelection()
                            event.accepted = true
                        }
                    }
                }
            }
        }

        ListView {
            id: historyList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Theme.space1
            model: root.filteredEntries
            currentIndex: root.currentIndex
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
            delegate: Squircle {
                id: row
                required property int index
                required property var modelData
                readonly property bool selected: index === root.currentIndex
                width: historyList.width
                height: Config.appearance.ink
                    ? (modelData.kind === "image" ? 56 : 44)
                    : modelData.kind === "image" ? Theme.u(1.5) : Theme.u(0.94)
                radius: Config.appearance.ink ? Theme.rCtl : Theme.u(0.33)
                color: root.copiedEntryId === modelData.id
                    ? Qt.alpha(Theme.success, 0.24)
                    // Selection on glass is a soft white wash, not a solid
                    // accent bar (glass redesign). Ink: an inkRaised chip.
                    : row.selected ? (Config.appearance.ink ? Theme.inkRaised : Qt.alpha(AdaptiveColor.glassText, 0.16))
                    : (!Config.appearance.ink && rowHover.hovered) ? Qt.alpha(AdaptiveColor.glassText, 0.07)
                    : "transparent"
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Config.appearance.ink ? 12 : Theme.u(0.28)
                    anchors.rightMargin: Config.appearance.ink ? 12 : Theme.u(0.28)
                    anchors.topMargin: Config.appearance.ink ? 0 : Theme.u(0.19)
                    anchors.bottomMargin: Config.appearance.ink ? 0 : Theme.u(0.19)
                    spacing: Theme.u(0.24)
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        RowLayout {
                            anchors.fill: parent
                            spacing: Theme.u(0.24)
                            Rectangle {
                                visible: modelData.kind === "image"
                                Layout.preferredWidth: visible ? (Config.appearance.ink ? 24 : Theme.u(1.22)) : 0
                                Layout.preferredHeight: visible ? (Config.appearance.ink ? 24 : Theme.u(1.0)) : 0
                                radius: Config.appearance.ink ? 8 : Theme.u(0.17)
                                clip: true
                                color: Config.appearance.ink ? Theme.inkRaised : Theme.surfaceContainer
                                Image {
                                    anchors.fill: parent
                                    source: ClipboardService.thumbnailSource(modelData.id)
                                    asynchronous: true
                                    cache: false
                                    fillMode: Image.PreserveAspectCrop
                                    sourceSize.width: Config.clipboard.thumbnailWidth
                                    sourceSize.height: Config.clipboard.thumbnailHeight
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: !ClipboardService.thumbnailSource(modelData.id)
                                    text: "󰋩"
                                    color: row.selected ? (Config.appearance.ink ? Theme.t1 : AdaptiveColor.glassText) : (Config.appearance.ink ? Theme.t2 : AdaptiveColor.glassTextDim)
                                    font.family: Config.appearance.monoFontFamily
                                }
                            }
                            Text {
                                visible: modelData.kind === "text"
                                text: "󰅌"
                                color: (Config.appearance.ink ? Theme.t1 : AdaptiveColor.activeFill)
                                font.family: Config.appearance.monoFontFamily
                            }
                            Text {
                                Layout.fillWidth: true
                                text: modelData.preview
                                color: (Config.appearance.ink ? Theme.t1 : AdaptiveColor.glassText)
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                font.family: Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily
                                font.pixelSize: Config.appearance.ink ? 13 : Theme.textBody
                                font.weight: Config.appearance.ink ? Font.Medium : Font.Normal
                            }
                        }
                        HoverHandler { id: rowHover }
                        TapHandler {
                            onTapped: {
                                root.currentIndex = index
                                ClipboardService.copy(modelData.id)
                            }
                        }
                    }
                    Item {
                        Layout.preferredWidth: Theme.u(0.5)
                        Layout.fillHeight: true
                        Text {
                            anchors.centerIn: parent
                            text: "󰆴"
                            color: deleteHover.hovered ? Theme.error
                                : (Config.appearance.ink ? Theme.t2 : AdaptiveColor.glassTextDim)
                            font.family: Config.appearance.monoFontFamily
                        }
                        HoverHandler { id: deleteHover }
                        TapHandler {
                            onTapped: {
                                root.currentIndex = index
                                ClipboardService.remove(modelData.id)
                            }
                        }
                    }
                }
                Behavior on color { ColorAnimation { duration: Animations.fast } }
                Component.onCompleted: ClipboardService.requestPreview(modelData)
            }
            Text {
                anchors.centerIn: parent
                visible: historyList.count === 0
                text: ClipboardService.loading ? "Loading clipboard…"
                    : ClipboardService.errorMessage || "No matching text entries"
                color: (Config.appearance.ink ? Theme.t2 : AdaptiveColor.glassTextDim)
                font.family: (Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily)
                font.pixelSize: Theme.textBody
            }
        }
    }
}
