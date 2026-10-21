pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "../core"
import "../components"

/**
 * IslandSwitcher -- the Alt+Tab face of the island. A row of running apps in
 * most-recently-used order: 56px real icons on ink, the selected one on an
 * inkRaised tile with a fillOn underline, a count badge for apps with more
 * than one window, and the selected app's name and window title underneath.
 *
 * Driven entirely by IslandController (switcherItems / switcherIndex). Clicking
 * an icon focuses that app and closes the switcher.
 */
Item {
    id: root

    required property var controller

    readonly property real s: DisplayScale.primary
    readonly property int cell: Math.round(56 * s)
    readonly property int gap: Math.round(12 * s)
    readonly property int pad: Math.round(24 * s)
    readonly property int topPad: Math.round(16 * s)
    readonly property int underlineRoom: Math.round(8 * s)
    readonly property var items: controller.switcherItems || []
    readonly property int selected: controller.switcherIndex
    readonly property var current: items[selected] || null
    readonly property string currentName: current
        ? (current.name || current.class) : ""

    function scrollToSelected(): void {
        const left = root.selected * (root.cell + root.gap)
        const right = left + root.cell
        if (left < strip.contentX)
            strip.contentX = left
        else if (right > strip.contentX + strip.width)
            strip.contentX = right - strip.width
    }

    onSelectedChanged: scrollToSelected()

    Flickable {
        id: strip
        x: root.pad
        y: root.topPad
        width: root.width - 2 * root.pad
        height: root.cell + root.underlineRoom
        clip: true
        interactive: false
        contentWidth: Math.max(width, row.width)
        contentHeight: height

        Behavior on contentX {
            NumberAnimation { duration: Animations.fast; easing.type: Easing.OutCubic }
        }

        Row {
            id: row
            x: Math.max(0, (strip.width - width) / 2)
            spacing: root.gap

            Repeater {
                model: root.items

                delegate: Item {
                    id: cell

                    required property var modelData
                    required property int index

                    readonly property bool isSelected: index === root.selected
                    readonly property string letter: String(modelData.class || "?")
                        .charAt(0).toUpperCase()

                    width: root.cell
                    height: root.cell

                    Squircle {
                        anchors.fill: parent
                        radius: Theme.rCtl
                        // Ink: inkRaised tile. Glass (ink off): a faint white
                        // wash, since the pill behind is translucent.
                        color: Config.appearance.ink
                            ? Theme.inkRaised : Qt.rgba(1, 1, 1, 0.14)
                        visible: cell.isSelected
                    }

                    Image {
                        id: icon
                        anchors.centerIn: parent
                        width: Math.round(36 * root.s)
                        height: width
                        source: cell.modelData.iconName
                            ? Quickshell.iconPath(cell.modelData.iconName, true) : ""
                        sourceSize.width: width * 2
                        sourceSize.height: height * 2
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        smooth: true
                        visible: status === Image.Ready
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: !icon.visible
                        text: cell.letter
                        color: Theme.t2
                        font.family: Theme.fontUi
                        font.pixelSize: Math.round(20 * root.s)
                        font.weight: Font.DemiBold
                    }

                    Rectangle {
                        visible: cell.isSelected
                        width: Math.round(20 * root.s)
                        height: Math.round(2 * root.s)
                        radius: height / 2
                        color: Theme.fillOn
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: parent.height + Math.round(6 * root.s) - height
                    }

                    Rectangle {
                        visible: cell.modelData.windowCount > 1
                        anchors.right: parent.right
                        anchors.top: parent.top
                        width: Math.round(16 * root.s)
                        height: width
                        radius: width / 2
                        color: Theme.fillOn

                        Text {
                            anchors.centerIn: parent
                            text: cell.modelData.windowCount
                            color: Theme.glyphOn
                            font.family: Theme.fontUi
                            font.pixelSize: Math.round(11 * root.s)
                            font.weight: Font.DemiBold
                        }
                    }

                    TapHandler {
                        onTapped: root.controller.commitSwitcherAt(cell.index)
                    }
                }
            }
        }
    }

    Text {
        id: nameText
        x: root.pad
        y: strip.y + strip.height + Math.round(10 * root.s)
        width: root.width - 2 * root.pad
        text: root.currentName
        color: Theme.t1
        elide: Text.ElideRight
        font.family: Theme.fontUi
        font.pixelSize: Math.round(13 * root.s)
        font.weight: Font.DemiBold
    }

    Text {
        x: root.pad
        y: nameText.y + nameText.implicitHeight + Math.round(2 * root.s)
        width: root.width - 2 * root.pad
        text: root.current ? (root.current.title || "") : ""
        color: Theme.t2
        elide: Text.ElideRight
        font.family: Theme.fontUi
        font.pixelSize: Math.round(12 * root.s)
        font.weight: Font.Medium
    }
}
