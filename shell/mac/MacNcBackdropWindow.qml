import QtQuick
import Quickshell
import Quickshell.Wayland

/**
 * MacNcBackdropWindow -- the feathered backdrop behind the Notification Center
 * (namespace qml-rice:mac-nc-backdrop). Its alpha is the mask the compositor
 * glass plugin blurs by, so it must hold nothing but this gradient. It sits on
 * WlrLayer.Top, under the NC's Overlay layer and above app windows, and takes
 * no input. Its own file so offscreen harnesses never compile a PanelWindow
 * (see MacTokens.layerShell). `owner` is the MacNotificationCenter that loads it.
 */
PanelWindow {
    id: win

    property var owner: null

    visible: owner ? owner.present : false
    anchors { top: true; bottom: true; right: true }
    implicitWidth: MacTokens.s(MacTokens.ncBackdropWidth)
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "qml-rice:mac-nc-backdrop"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // Empty region: every pointer event passes through to the windows below.
    mask: Region {}

    Rectangle {
        anchors.fill: parent
        opacity: win.owner ? win.owner.shown : 0
        gradient: Gradient {
            orientation: Gradient.Horizontal
            // Smoothstep alpha(t) = maxA * t * t * (3 - 2t), t runs 0 (left) to 1 (right).
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0) }
            GradientStop { position: 0.2; color: Qt.rgba(0, 0, 0, MacTokens.ncBackdropMaxAlpha * 0.104) }
            GradientStop { position: 0.4; color: Qt.rgba(0, 0, 0, MacTokens.ncBackdropMaxAlpha * 0.352) }
            GradientStop { position: 0.6; color: Qt.rgba(0, 0, 0, MacTokens.ncBackdropMaxAlpha * 0.648) }
            GradientStop { position: 0.8; color: Qt.rgba(0, 0, 0, MacTokens.ncBackdropMaxAlpha * 0.896) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, MacTokens.ncBackdropMaxAlpha) }
        }
    }
}
