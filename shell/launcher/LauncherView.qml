import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"
import "../components"

Item {
    id: root

    required property var provider
    property string placeholderText: "Search apps"
    property string emptyText: "No matches"
    property string searchIcon: "󰍉"
    property bool copyShortcutEnabled: false
    property var results: {
        provider.revision
        return provider.search(searchField.text, Config.launcher.resultLimit)
    }
    property int currentIndex: firstEnabledIndex()
    // Ink (Config.appearance.ink): 52px inkRaised search field, sentence-case
    // section captions from each result's group, no caret bead.
    readonly property bool ink: Config.appearance.ink
    signal dismissRequested()
    signal pageRequested(string page)

    function firstEnabledIndex(): int {
        for (let i = 0; i < results.length; ++i) {
            if (results[i].enabled)
                return i
        }
        return -1
    }

    function moveSelection(delta: int): void {
        if (results.length === 0)
            return
        let candidate = currentIndex
        for (let i = 0; i < results.length; ++i) {
            candidate = (candidate + delta + results.length) % results.length
            if (results[candidate].enabled)
                break
        }
        currentIndex = candidate
        resultList.positionViewAtIndex(currentIndex, ListView.Contain)
    }

    function activateCurrent(copyOnly: bool, newInstance: bool): void {
        if (currentIndex < 0 || currentIndex >= results.length)
            return
        const outcome = provider.execute(results[currentIndex], copyOnly, newInstance)
        if (!outcome?.handled)
            return
        if (outcome.page)
            pageRequested(outcome.page)
        else if (outcome.dismiss)
            dismissRequested()
    }

    onResultsChanged: {
        currentIndex = firstEnabledIndex()
        if (visible)
            resultRefresh.restart()
    }
    onVisibleChanged: {
        if (visible) {
            if (provider.opened)
                provider.opened()
            searchField.text = ""
            Qt.callLater(() => searchField.forceActiveFocus())
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.space2

        Squircle {
            Layout.fillWidth: true
            Layout.preferredHeight: root.ink ? 52 : Theme.u(1.39)
            radius: root.ink ? Theme.rCtl : Theme.u(0.4)
            color: root.ink ? Theme.inkRaised : Theme.surfaceContainerHigh

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: root.ink ? Theme.space4 : Theme.space3
                anchors.rightMargin: root.ink ? Theme.space4 : Theme.space3
                spacing: root.ink ? 12 : Theme.space2

                Text {
                    text: root.searchIcon
                    color: root.ink ? Theme.t2 : AdaptiveColor.activeFill
                    font.family: Config.appearance.monoFontFamily
                    font.pixelSize: root.ink ? 20 : Theme.iconSmall
                }

                TextInput {
                    id: searchField
                    Layout.fillWidth: true
                    color: root.ink ? Theme.t1 : AdaptiveColor.glassText
                    selectionColor: Theme.primaryContainer
                    selectedTextColor: Theme.primaryContainerText
                    clip: true
                    selectByMouse: true
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: root.ink ? Theme.fontUi : Config.appearance.fontFamily
                    font.pixelSize: root.ink ? 20 : Theme.textBody
                    font.weight: root.ink ? Font.Medium : Font.Normal

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: searchField.text.length === 0
                        text: root.placeholderText
                        color: root.ink ? Theme.t3 : AdaptiveColor.glassTextDim
                        font: searchField.font
                    }

                    Keys.onPressed: event => {
                        const copyModifier = event.modifiers & Qt.ControlModifier
                        if (event.key === Qt.Key_Down) {
                            root.moveSelection(1)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Up) {
                            root.moveSelection(-1)
                            event.accepted = true
                        } else if (root.copyShortcutEnabled && copyModifier
                                && (event.key === Qt.Key_C
                                    || event.key === Qt.Key_Return
                                    || event.key === Qt.Key_Enter)) {
                            root.activateCurrent(true, false)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Return
                                || event.key === Qt.Key_Enter) {
                            // Shift+Enter: a new instance of a running app.
                            root.activateCurrent(false,
                                (event.modifiers & Qt.ShiftModifier) !== 0)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Escape) {
                            root.dismissRequested()
                            event.accepted = true
                        }
                    }
                }

                Text {
                    text: root.results.length.toString()
                    color: root.ink ? Theme.t3 : AdaptiveColor.glassTextDim
                    font.family: Config.appearance.monoFontFamily
                    font.pixelSize: root.ink ? 12 : Theme.textSmall
                }
            }
        }

        // Wraps the ListView so the caret bead below can share its
        // coordinate space without scrolling WITH the content -- it tracks
        // currentItem's viewport position frame by frame instead.
        Item {
            id: resultListWrap
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: resultList
                anchors.fill: parent
                clip: true
                spacing: root.ink ? 2 : Theme.space1
                model: root.results
                currentIndex: root.currentIndex

                add: Transition {
                    ParallelAnimation {
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Animations.fast; easing.type: Animations.emphasizedEase }
                        NumberAnimation { property: "scale"; from: 0.98; to: 1; duration: Animations.fast; easing.type: Animations.emphasizedEase }
                    }
                }
                remove: Transition {
                    NumberAnimation { property: "opacity"; to: 0; duration: Math.round(Animations.fast * 0.6); easing.type: Animations.emphasizedEase }
                }
                displaced: Transition {
                    NumberAnimation { properties: "x,y"; duration: Animations.normal; easing.type: Animations.standardEase }
                }

                delegate: Column {
                    id: rowColumn
                    required property int index
                    required property var modelData
                    width: resultList.width
                    spacing: 0

                    // Ink only: a sentence-case caption (Geist 12/500 t3)
                    // above the first row of each group. Invisible otherwise,
                    // so Column ignores it and the rows are unchanged.
                    Item {
                        width: parent.width
                        height: rowColumn.index === 0 ? 32 : 44
                        visible: root.ink && (rowColumn.index === 0
                            || root.results[rowColumn.index - 1]?.group !== rowColumn.modelData.group)

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 10
                            text: rowColumn.modelData.group ?? ""
                            color: Theme.t3
                            font.family: Theme.fontUi
                            font.pixelSize: 12
                            font.weight: Font.Medium
                        }
                    }

                    PaletteResult {
                        width: rowColumn.width
                        result: rowColumn.modelData
                        selected: rowColumn.index === root.currentIndex
                        onPointed: root.currentIndex = rowColumn.index
                        onActivated: {
                            root.currentIndex = rowColumn.index
                            root.activateCurrent(false, false)
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: root.results.length === 0
                    text: root.emptyText
                    color: root.ink ? Theme.t3 : AdaptiveColor.glassTextDim
                    font.family: root.ink ? Theme.fontUi : Config.appearance.fontFamily
                    font.pixelSize: root.ink ? 14 : Theme.textBody
                }
            }

            // Selection caret: tracks the current row's viewport position
            // (currentItem.y - contentY), NOT the row's own list-local y,
            // so it stays visually correct while the list scrolls.
            Bead {
                form: "caret"
                color: AdaptiveColor.activeFill
                dotSize: Theme.u(0.16)
                visible: resultList.currentItem !== null && !root.ink
                target: Qt.point(Theme.u(0.05),
                    resultList.currentItem
                        ? resultList.currentItem.y - resultList.contentY
                            + resultList.currentItem.height / 2
                        : 0)
            }
        }
    }

    SequentialAnimation {
        id: resultRefresh
        NumberAnimation { target: resultList; property: "opacity"; to: 0.78; duration: Math.round(Animations.fast * 0.35); easing.type: Animations.emphasizedEase }
        NumberAnimation { target: resultList; property: "opacity"; to: 1; duration: Math.round(Animations.fast * 0.65); easing.type: Animations.emphasizedEase }
    }
}
