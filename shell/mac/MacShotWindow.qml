import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"

/**
 * MacShotWindow -- the layer window for the screenshot thumbnail (namespace
 * qml-rice:mac-shot). Its own file so offscreen harnesses never compile a
 * PanelWindow (see MacTokens.layerShell). MacStyleRoot loads it with
 * `active: MacTokens.layerShell`.
 */
PanelWindow {
    id: window

    readonly property MacShotThumbnail thumb: shot
    readonly property bool shown: shot.current !== null

    anchors { bottom: true; right: true }
    margins.bottom: MacTokens.s(MacTokens.shotInsetBottom)
    margins.right: MacTokens.s(MacTokens.shotInsetRight)
    implicitWidth: shot.implicitWidth
    implicitHeight: shot.implicitHeight
    visible: shown
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qml-rice:mac-shot"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // Clicks outside the card pass through to the windows underneath.
    mask: Region { item: shot }

    MacShotThumbnail {
        id: shot
    }
}
