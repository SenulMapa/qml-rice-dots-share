import QtQuick
import Quickshell
import Quickshell.Wayland

/**
 * MacNcCorner -- the top-right hot corner of every monitor. A click toggles the
 * Notification Center on that monitor (namespace qml-rice:mac-nc-corner). The
 * surface paints nothing and has no input mask, so it takes the click itself.
 * Loaded by MacStyleRoot only with layer shell (see MacTokens.layerShell).
 * `center` is the MacNotificationCenter to toggle.
 */
Variants {
    id: corners

    property var center: null

    model: Quickshell.screens

    delegate: PanelWindow {
        id: corner

        required property var modelData

        screen: modelData
        anchors { top: true; right: true }
        implicitWidth: MacTokens.ncCornerSize
        implicitHeight: MacTokens.ncCornerSize
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "qml-rice:mac-nc-corner"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: "transparent"

        MouseArea {
            anchors.fill: parent
            // On press, not click: a click needs the release inside a tiny target,
            // and the pointer drifts while the button is down (seen live 21 Oct).
            onPressed: if (corners.center) corners.center.requestOn("toggle", corner.modelData)
        }
    }
}
