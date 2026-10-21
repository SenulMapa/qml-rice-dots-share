import QtQuick
import "../components"
import "../core"

/**
 * MacInkPill -- a small text pill on ink (Clear All, group Clear / Show less,
 * Show N more). inkRaised2 fill, t2 text, fully rounded. Sizes are pt, scaled
 * with MacTokens.s() here, like every other mac geometry.
 */
Item {
    id: root

    property string text: ""
    property real heightPt: MacTokens.ncPillHeight
    property real textPt: MacTokens.ncPillTextSize

    signal tapped()

    implicitHeight: MacTokens.s(root.heightPt)
    implicitWidth: label.implicitWidth + 2 * MacTokens.s(MacTokens.ncPillPadX)

    Squircle {
        anchors.fill: parent
        radius: height / 2
        color: MacTokens.ncPillFill
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: MacTokens.labelSecondary
        font.family: MacTokens.textFamily
        font.pixelSize: MacTokens.s(root.textPt)
        font.weight: Font.Medium
    }

    TapHandler { onTapped: root.tapped() }
}
