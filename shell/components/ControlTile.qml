import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"

/**
 * ControlTile - the grid tile (Wi-Fi / Audio / Bluetooth / Peace / Night
 * Light). Split tap target, unchanged in spirit from before the reskin: the
 * icon disc toggles the underlying state, the rest of the body activates
 * (opens a satellite for Wi-Fi/Audio/Bluetooth, or IS the toggle itself for
 * Peace/Night Light, which set `expandable: false` so every tap lands on
 * `activated()`).
 */
Squircle {
    id: root

    property string title: ""
    property string detail: ""
    property string icon: ""
    property bool checked: false
    property bool available: true
    property bool expandable: false
    property bool expanded: false

    signal activated()
    signal toggleRequested()

    activeFocusOnTab: available
    opacity: available ? 1 : 0.42
    radius: Theme.u(0.34)
    color: checked ? AdaptiveColor.activeFill : Theme.surfaceContainer

    Item {
        id: iconDisc
        x: Theme.u(0.23)
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.u(0.8)
        height: Theme.u(0.8)

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: root.checked ? Theme.surfaceContainerLow : Theme.surface
        }

        Text {
            anchors.centerIn: parent
            text: root.icon
            color: root.checked ? AdaptiveColor.activeFill : AdaptiveColor.glassText
            font.family: Config.appearance.monoFontFamily
            font.pixelSize: Theme.u(0.36)
        }
    }

    ColumnLayout {
        anchors.left: iconDisc.right
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Theme.u(0.2)
        anchors.rightMargin: Theme.u(0.22)
        spacing: 2

        Text {
            Layout.fillWidth: true
            text: root.title
            color: root.checked ? Theme.accentFillText : AdaptiveColor.glassText
            elide: Text.ElideRight
            font.family: Config.appearance.fontFamily
            font.pixelSize: Theme.u(0.3)
            font.weight: Font.Medium
        }

        Text {
            Layout.fillWidth: true
            text: root.detail.toUpperCase()
            color: root.checked ? Qt.alpha(Theme.accentFillText, 0.75) : AdaptiveColor.glassTextDim
            elide: Text.ElideRight
            font.family: Config.appearance.monoFontFamily
            font.pixelSize: Theme.u(0.24)
            font.letterSpacing: Theme.u(0.24) * 0.1
        }
    }

    HoverHandler { id: tileHover; enabled: root.available }
    TapHandler {
        enabled: root.available
        onTapped: eventPoint => {
            root.forceActiveFocus()
            const point = eventPoint.position
            const iconHit = root.expandable && point.x >= iconDisc.x
                && point.x <= iconDisc.x + iconDisc.width
                && point.y >= iconDisc.y
                && point.y <= iconDisc.y + iconDisc.height
            if (iconHit)
                root.toggleRequested()
            else
                root.activated()
        }
    }
    Keys.onPressed: event => {
        if (!root.available)
            return
        if (root.expandable && event.key === Qt.Key_Space) {
            root.toggleRequested()
            event.accepted = true
        } else if (event.key === Qt.Key_Space || event.key === Qt.Key_Return
                || event.key === Qt.Key_Enter) {
            root.activated()
            event.accepted = true
        }
    }

    Behavior on color { ColorAnimation { duration: Animations.fast } }
}
