import QtQuick
import "../core"
import "../components"

/**
 * MacCcSlider -- a full-width Control Center module (spec 3.4): 292 x 63 glass
 * capsule with a title and one level track between two glyphs (Display,
 * Sound). The track has no knob, as in the Tahoe capture. Every value comes
 * from MacTokens.
 *
 * `value` is 0..1 from the service. While the user drags, the track follows
 * the pointer and `moved(v)` reports each position (0..1). The caller writes
 * it to the service; nothing here changes a level on its own.
 */
TahoeSurface {
    id: root

    property string title: ""
    property string leftIcon: ""
    property string rightIcon: ""
    property real value: 0
    property bool available: true

    signal moved(real v)

    readonly property real shownValue: drag.pressed ? drag.dragValue : Math.max(0, Math.min(1, value))

    kind: "controlcenter"
    fill: MacTokens.ccModuleFill
    width: MacTokens.s(MacTokens.ccSliderWidth)
    height: MacTokens.s(MacTokens.ccSliderHeight)
    radius: MacTokens.s(MacTokens.ccTileRadius)
    opacity: root.available ? 1 : MacTokens.ccDisabledAlpha

    readonly property real trackX: MacTokens.s(MacTokens.ccSliderTrackStart)
    readonly property real trackWidth: MacTokens.s(MacTokens.ccSliderTrackEnd - MacTokens.ccSliderTrackStart)
    readonly property real trackCentreY: MacTokens.s(MacTokens.ccSliderRowCentre)

    Text {
        x: MacTokens.s(MacTokens.ccSliderPadX)
        y: MacTokens.s(MacTokens.ccSliderTitleY)
        text: root.title
        color: MacTokens.ccTitleColor
        font.family: MacTokens.textFamily
        font.pixelSize: MacTokens.s(MacTokens.ccTitleSize)
        font.weight: Font.DemiBold
    }

    Icon {
        x: MacTokens.s(MacTokens.ccSliderIconX) - width / 2
        y: root.trackCentreY - height / 2
        name: root.leftIcon
        size: MacTokens.s(MacTokens.ccSliderIconSize)
        color: MacTokens.ccTitleColor
    }

    Icon {
        x: MacTokens.s(MacTokens.ccSliderIconRightX) - width / 2
        y: root.trackCentreY - height / 2
        name: root.rightIcon
        size: MacTokens.s(MacTokens.ccSliderIconSize)
        color: MacTokens.ccTitleColor
    }

    // Idle part of the track.
    Rectangle {
        x: root.trackX
        y: root.trackCentreY - height / 2
        width: root.trackWidth
        height: MacTokens.s(MacTokens.ccSliderTrack)
        radius: MacTokens.s(MacTokens.ccTrackRadius)
        color: MacTokens.ccTrackIdle
    }

    // Filled part of the track.
    Rectangle {
        x: root.trackX
        y: root.trackCentreY - height / 2
        width: root.trackWidth * root.shownValue
        height: MacTokens.s(MacTokens.ccSliderTrack)
        radius: MacTokens.s(MacTokens.ccTrackRadius)
        color: MacTokens.ccTrackFill
    }

    // Hit area: the full track height of a slider row, not just the bar.
    MouseArea {
        id: drag
        property real dragValue: 0
        x: root.trackX - MacTokens.s(MacTokens.ccSliderPadX) / 2
        width: root.trackWidth + MacTokens.s(MacTokens.ccSliderPadX)
        y: root.trackCentreY - MacTokens.s(MacTokens.ccSliderHandle) / 2
        height: MacTokens.s(MacTokens.ccSliderHandle)
        enabled: root.available
        preventStealing: true

        // mouseX is local to this area; x maps it back onto the module.
        function report(mouseX: real): void {
            const offset = mouseX + x
            dragValue = Math.max(0, Math.min(1, (offset - root.trackX) / root.trackWidth))
            root.moved(dragValue)
        }

        onPressed: mouse => report(mouse.x)
        onPositionChanged: mouse => { if (pressed) report(mouse.x) }
    }
}
