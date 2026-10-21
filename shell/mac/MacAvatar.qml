import QtQuick
import Quickshell
import Quickshell.Widgets
import "../components"
import "MacFormat.js" as Format

/**
 * MacAvatar -- the sender or app avatar on a Tahoe banner and notification
 * card. Shows the image once it loads; until then a letter on the Tahoe
 * accent (systemRed when critical). Every value comes from MacTokens.
 *
 * Mac-only on purpose: components/NotificationAvatar.qml is shared with the
 * pill, and it draws its letter in Config.appearance.fontFamily and its fill
 * from the shell accent. Neither belongs on a mac surface.
 */
Item {
    id: root

    required property var entry
    property real size: MacTokens.s(MacTokens.bannerIconSize)
    // Corner radius of an image icon. Negative (default) keeps the circle banners use.
    property real imageRadius: -1
    // Letter fallback colours. Banners keep the Tahoe accent; cards pass ink.
    property color fallbackFill: MacTokens.accentBlue
    property color fallbackText: MacTokens.accentOn

    implicitWidth: size
    implicitHeight: size

    readonly property bool critical: entry?.critical ?? false

    // Resolved app icon: the app icon name, then the desktop entry (by id or
    // heuristic lookup) and its icon, then the app name. Empty when none
    // resolves. Same lookup family as the pill's NotificationAvatar.
    readonly property string appIconPath: {
        const names = [entry?.appIcon, entry?.desktopEntry, entry?.appName]
        for (const name of names) {
            if (!name)
                continue
            const path = Quickshell.iconPath(name, true)
            if (path)
                return path
        }
        if (typeof DesktopEntries === "undefined")
            return ""
        for (const name of [entry?.desktopEntry, entry?.appName]) {
            if (!name)
                continue
            const desktop = DesktopEntries.byId(name) || DesktopEntries.heuristicLookup(name)
            const path = desktop?.icon ? Quickshell.iconPath(desktop.icon, true) : ""
            if (path)
                return path
        }
        return ""
    }

    // Source priority lives in MacFormat.avatarSource (pure, tested):
    // app icon, then a stable notification image, then the letter. A
    // transient image://qsimage handle is never bound here: it can expire
    // before or while the banner renders.
    readonly property string iconSource: Format.avatarSource(root.appIconPath, entry?.image ?? "")
    readonly property string initial: (entry?.appName || "?").trim().charAt(0).toUpperCase()

    Squircle {
        anchors.fill: parent
        visible: avatarImage.status !== Image.Ready
        radius: width / 2
        color: root.critical ? MacTokens.criticalFill : root.fallbackFill

        Text {
            anchors.centerIn: parent
            text: root.initial
            color: root.fallbackText
            font.family: MacTokens.displayFamily
            font.pixelSize: Math.round(root.size * 0.46)
            font.weight: Font.DemiBold
        }
    }

    ClippingRectangle {
        anchors.fill: parent
        radius: root.imageRadius >= 0 ? root.imageRadius : width / 2
        color: "transparent"
        visible: avatarImage.status === Image.Ready

        Image {
            id: avatarImage
            anchors.fill: parent
            source: root.iconSource
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
        }
    }
}
