import QtQuick
import Quickshell
import Quickshell.Widgets
import "../core"
import "../services"

/**
 * NotificationAvatar -- extracted from panels/NotificationCard.qml so the
 * control-centre mini list, the full NotificationCenter and
 * island/IslandNotification.qml's popup all render the exact same avatar and
 * cannot drift apart. Letter avatar, or the app image once it loads; a
 * critical entry gets an error-filled avatar instead of a boxed "CRITICAL"
 * badge, matching the card.
 */
Item {
    id: root

    required property var entry
    property real size: Theme.u(0.52)

    implicitWidth: size
    implicitHeight: size

    readonly property bool critical: entry?.critical ?? false
    readonly property color avatarFill: root.critical ? Theme.error : AdaptiveColor.activeFill
    readonly property color avatarText: root.critical
        ? Theme.foregroundFor(Theme.error) : Theme.accentFillText
    readonly property string iconSource: {
        if (entry?.image)
            return entry.image
        return entry?.appIcon ? Quickshell.iconPath(entry.appIcon, true) : ""
    }
    // Ink: a sender image is the avatar and the app icon becomes an 18px
    // badge; with no sender image the app icon itself is the 40px avatar.
    readonly property bool inkMode: Config.appearance.ink
    readonly property bool hasSenderImage: inkMode && !!entry?.image
    readonly property string appIconSource: entry?.appIcon
        ? Quickshell.iconPath(entry.appIcon, true) : ""
    readonly property string initial: (entry?.appName || "?").trim().charAt(0).toUpperCase()

    Rectangle {
        anchors.fill: parent
        visible: !root.inkMode && avatarImage.status !== Image.Ready
        radius: width / 2
        color: root.avatarFill
        Text {
            anchors.centerIn: parent
            text: root.initial
            color: root.avatarText
            font.family: Config.appearance.fontFamily
            // Scales with the avatar -- the card (0.52u) and the popup
            // (0.78u) share this component but not its size.
            font.pixelSize: Math.round(root.size * 0.4615)
            font.weight: Font.Bold
        }
    }
    Image {
        id: avatarImage
        anchors.fill: parent
        source: root.iconSource
        asynchronous: true
        fillMode: Image.PreserveAspectCrop
        visible: !root.inkMode && status === Image.Ready
    }

    // Ink: circular avatar (sender image, or the app icon when there is none).
    ClippingRectangle {
        visible: root.inkMode
        anchors.fill: parent
        radius: width / 2
        color: Theme.inkRaised

        Image {
            anchors.fill: parent
            source: root.hasSenderImage ? root.iconSource : root.appIconSource
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
            visible: status === Image.Ready
        }
    }

    // Ink: the 18px real-app-icon badge, bottom-right, ringed in ink (2px).
    Item {
        visible: root.hasSenderImage
        width: 22
        height: 22
        anchors.right: parent.right
        anchors.rightMargin: -6
        anchors.bottom: parent.bottom
        anchors.bottomMargin: -6

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Theme.ink
        }

        Image {
            anchors.centerIn: parent
            width: 18
            height: 18
            source: root.appIconSource
            sourceSize.width: 36
            sourceSize.height: 36
            asynchronous: true
            fillMode: Image.PreserveAspectFit
            visible: status === Image.Ready
        }
    }
}
