import QtQuick
import QtQuick.Layouts
import Quickshell
import "../components"
import "../core"

/**
 * MacSpotlightResult -- one Spotlight row (spec 3.5): icon, title, subtitle
 * and a right-aligned kind label, on a rounded selection highlight. Every
 * geometry value is MacTokens (pt), scaled with MacTokens.s().
 */
Squircle {
    id: root

    required property var result
    property bool selected: false
    signal activated()
    signal pointed()

    // Kind label: what the row is, shown right-aligned (spec 3.5).
    readonly property var kindLabels: ({
        "application": "Application",
        "file": "File",
        "clipboard": "Clipboard",
        "action": "Command",
        "calculator": "Calculator",
        "web-search": "Web Search",
        "workspace": "Workspace"
    })
    readonly property string kindText: kindLabels[root.result.kind] ?? (root.result.badge ?? "")

    implicitHeight: MacTokens.s(MacTokens.spotlightRowHeight)
    height: MacTokens.s(MacTokens.spotlightRowHeight)
    radius: MacTokens.s(MacTokens.spotlightRowRadius)
    color: selected ? MacTokens.spotlightSelectedFill
        : hover.hovered ? Qt.rgba(0, 0, 0, 0.05) : "transparent"
    opacity: root.result.enabled === false ? 0.46 : 1

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: MacTokens.s(MacTokens.spotlightListInset)
        anchors.rightMargin: MacTokens.s(MacTokens.spotlightListInset)
        spacing: MacTokens.s(MacTokens.spotlightIconGap)

        Item {
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: MacTokens.s(MacTokens.spotlightIconSize)
            Layout.preferredHeight: MacTokens.s(MacTokens.spotlightIconSize)

            Image {
                id: themedIcon
                anchors.fill: parent
                visible: root.result.iconKind === "theme"
                source: visible && root.result.icon
                    ? Quickshell.iconPath(root.result.icon, true) : ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
            }

            Icon {
                anchors.centerIn: parent
                visible: !!root.result.lucide
                name: root.result.lucide ?? ""
                size: MacTokens.s(MacTokens.spotlightIconSize) * 0.6
                color: MacTokens.onSurface(0.7)
            }

            Text {
                anchors.centerIn: parent
                visible: !root.result.lucide && themedIcon.status !== Image.Ready
                text: root.result.iconKind === "glyph" ? (root.result.icon ?? "") : ""
                color: MacTokens.onSurface(0.7)
                font.family: MacTokens.displayFamily
                font.pixelSize: MacTokens.s(MacTokens.spotlightIconSize) * 0.6
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 1

            Text {
                Layout.fillWidth: true
                text: root.result.title ?? ""
                color: MacTokens.onSurface(0.85)
                elide: Text.ElideRight
                maximumLineCount: 1
                font.family: MacTokens.textFamily
                font.pixelSize: MacTokens.s(MacTokens.spotlightTitleSize)
            }

            Text {
                Layout.fillWidth: true
                visible: text.length > 0
                text: root.result.subtitle ?? ""
                color: MacTokens.onSurface(0.5)
                elide: Text.ElideRight
                maximumLineCount: 1
                font.family: MacTokens.textFamily
                font.pixelSize: MacTokens.s(MacTokens.spotlightSubtitleSize)
            }
        }

        Text {
            Layout.alignment: Qt.AlignVCenter
            Layout.rightMargin: MacTokens.s(MacTokens.spotlightListInset)
            visible: text.length > 0
            text: root.kindText
            color: MacTokens.onSurface(0.45)
            font.family: MacTokens.textFamily
            font.pixelSize: MacTokens.s(MacTokens.spotlightSubtitleSize)
        }
    }

    HoverHandler {
        id: hover
        enabled: root.result.enabled !== false
        onHoveredChanged: if (hovered) root.pointed()
    }
    TapHandler {
        enabled: root.result.enabled !== false && root.result.executable !== false
        onTapped: root.activated()
    }
}
