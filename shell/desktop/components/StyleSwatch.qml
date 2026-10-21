// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   S T Y L E   S W A T C H                                                │
// │   a widget style in miniature · a capsule with two letters on it         │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick
import "../services" as DeskServices
import "../../components"


// A miniature of one of the four desktop widget styles: the capsule in the
// given ink with a two-letter type sample. Shared by the settings page and
// the inspector. `ink` comes from `DeskServices.DeskDesktopService.inkFor`, already inverted
// for the accent style.
Squircle {
    id: root

    property string style: "capsule"
    property var ink: null

    // Drawn at one size and scaled: 34 by 26 at a factor of one.
    property real factor: 1

    readonly property bool onPicture: root.style === "bare" || root.style === "outline"
    readonly property color text: root.ink ? root.ink.text : DeskServices.DeskTheme.text

    implicitWidth: Math.round(34 * root.factor)
    implicitHeight: Math.round(26 * root.factor)
    radius: 7 * root.factor
    color: root.onPicture || !root.ink ? "transparent" : root.ink.ground
    borderColor: root.style === "outline"
        ? Qt.rgba(root.text.r, root.text.g, root.text.b, 0.55)
        : (root.style === "capsule" && root.ink ? root.ink.border : "transparent")
    borderWidth: root.style === "accent" || root.style === "bare" ? 0 : 1

    Text {
        anchors.centerIn: parent
        text: "Aa"
        font.family: DeskServices.DeskTheme.fontFamily
        font.pixelSize: Math.round(11 * root.factor)
        font.weight: Font.DemiBold
        color: root.text
    }
}
