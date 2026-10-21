import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"

/**
 * ConnectivityRow - a single row in a Wi-Fi/Bluetooth/Audio satellite list.
 *
 * Matches AudioSatelliteContent's device rows: no card fill, no filled
 * pill -- a plain row with a hover-only highlight. The active/connected
 * row is marked by accent-coloured title text plus a small accent check
 * glyph, exactly like the audio satellite's output/input device lists.
 * Left click on an inactive row connects/pairs/selects it (`activated`);
 * on the active row (when `informationAvailable`) it opens the details
 * subview instead -- the same subview the old (i) button opened. Right
 * click opens details from any row, active or not.
 */
Squircle {
    id: root

    property string title: ""
    property string detail: ""
    property string icon: "󰡺"
    property string iconName: ""      // Lucide name; drawn by Icon when ink is on
    property bool selected: false
    property bool available: true
    property bool busy: false
    property bool informationAvailable: false

    signal activated()
    signal informationRequested()

    activeFocusOnTab: available
    opacity: available ? 1 : 0.46
    // Ink: a 44px row with no fill except the selected row (inkRaised, r14).
    implicitHeight: Config.appearance.ink ? 44
        : content.implicitHeight + Theme.u(0.25) * 2
    radius: Config.appearance.ink ? Theme.rCtl : Theme.u(0.34)
    color: Config.appearance.ink
        ? (root.selected ? Theme.inkRaised : "transparent")
        : rowHover.hovered || activeFocus
            ? Qt.alpha(AdaptiveColor.glassTextDim, 0.08) : "transparent"

    RowLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Theme.u(0.3)
        anchors.rightMargin: Theme.u(0.3)
        spacing: Theme.u(0.3)

        Icon {
            id: rowLucide
            visible: Config.appearance.ink && root.iconName.length > 0
            Layout.alignment: Qt.AlignVCenter
            name: root.iconName
            size: 18
            color: root.selected ? Theme.t1 : Theme.t2

            RotationAnimation on rotation {
                running: root.busy && !Config.appearance.reducedMotion
                loops: Animation.Infinite
                from: 0
                to: 360
                duration: 900
                onStopped: rowLucide.rotation = 0
            }
        }

        Text {
            id: rowIcon
            visible: !rowLucide.visible
            text: root.busy ? "󰡌" : root.icon
            color: Config.appearance.ink
                ? (root.selected ? Theme.t1 : Theme.t2) : AdaptiveColor.glassText
            font.family: Config.appearance.monoFontFamily
            font.pixelSize: Config.appearance.ink ? 18 : Theme.u(0.4)

            RotationAnimation on rotation {
                running: root.busy && !Config.appearance.reducedMotion
                loops: Animation.Infinite
                from: 0
                to: 360
                duration: 900
                onStopped: rowIcon.rotation = 0
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                Layout.fillWidth: true
                text: root.title
                color: Config.appearance.ink ? Theme.t1
                    : root.selected ? AdaptiveColor.activeFill : AdaptiveColor.glassText
                elide: Text.ElideRight
                font.family: Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily
                font.pixelSize: Config.appearance.ink ? 13 : Theme.u(0.36)
                font.weight: Config.appearance.ink ? Font.DemiBold : Font.Medium
            }
            Text {
                Layout.fillWidth: true
                visible: !Config.appearance.ink
                text: root.detail
                color: AdaptiveColor.glassTextDim
                elide: Text.ElideRight
                font.family: Config.appearance.fontFamily
                font.pixelSize: Theme.u(0.28)
            }
        }

        // Ink: the trailing state is plain 13/500 t2 text ("Connected",
        // "Not connected", "Pair"), not a glyph.
        Text {
            visible: Config.appearance.ink && root.detail !== ""
            text: root.detail
            color: Theme.t2
            elide: Text.ElideRight
            font.family: Theme.fontUi
            font.pixelSize: 13
            font.weight: Font.Medium
        }

        Text {
            visible: root.selected && (!Config.appearance.ink || root.detail === "")
            text: "󰄬"
            color: Config.appearance.ink ? Theme.t1 : AdaptiveColor.activeFill
            font.family: Config.appearance.monoFontFamily
            font.pixelSize: Theme.u(0.32)
        }
    }

    HoverHandler { id: rowHover; enabled: root.available }
    TapHandler {
        acceptedButtons: Qt.LeftButton
        enabled: root.available
        onTapped: {
            root.forceActiveFocus()
            if (root.selected && root.informationAvailable)
                root.informationRequested()
            else
                root.activated()
        }
    }
    TapHandler {
        acceptedButtons: Qt.RightButton
        enabled: root.available && root.informationAvailable
        onTapped: root.informationRequested()
    }
    Keys.onPressed: event => {
        if (!root.available)
            return
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                || event.key === Qt.Key_Space) {
            if (root.selected && root.informationAvailable)
                root.informationRequested()
            else
                root.activated()
            event.accepted = true
        }
    }

    Behavior on color { ColorAnimation { duration: Animations.fast } }
}
