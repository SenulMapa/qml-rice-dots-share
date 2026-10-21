import QtQuick
import "../core"
import "../components"

/**
 * MacCcToggle -- a round Control Center toggle (spec 3.4): a 62 pt glass
 * circle with one glyph. Active is the accent fill with a white glyph; idle
 * is glass with an accent glyph. Every value comes from MacTokens.
 *
 * `activated()` fires on tap. `inert: true` draws the toggle but takes no
 * input (Screen Mirroring, which has no hook in the shell yet).
 */
TahoeSurface {
    id: root

    property string icon: ""
    property bool active: false
    property bool available: true
    property bool inert: false

    signal activated()

    kind: "controlcenter"
    fill: MacTokens.ccModuleFill
    width: MacTokens.s(MacTokens.ccRoundDiameter)
    height: width
    radius: width / 2
    opacity: root.available ? 1 : MacTokens.ccDisabledAlpha

    // Active: white disc with a blue glyph. Idle: translucent disc, white glyph.
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.active ? MacTokens.ccDiscFill : MacTokens.ccDiscIdleFill
        Behavior on color { ColorAnimation { duration: MacTokens.ccMotionMs / 2 } }
    }

    Icon {
        anchors.centerIn: parent
        name: root.icon
        size: MacTokens.s(MacTokens.ccToggleIconSize)
        color: root.active ? MacTokens.ccActiveGlyph : MacTokens.ccIconIdle
    }

    TapHandler {
        enabled: root.available && !root.inert
        onTapped: root.activated()
    }
}
