pragma ComponentBehavior: Bound
import QtQuick
import "../desktop/services" as Desk
import "../services" as Services

// ported from impasto lock/LockPower.qml, verbatim except: Theme -> Desk.
// DeskTheme; SessionService.run(action) (impasto's own service, not
// present here) -> this shell's services/SessionService.qml schedule(action)
// (same "arm on click one, run on click two" two-step, same action-string
// vocabulary: "reboot"/"shutdown" are both members of SessionService's own
// isKnownAction() list). No suspend button, same as upstream -- it already
// has a shortcut and a button in the session panel here too.
Row {
    id: root

    property string armed: ""

    spacing: 8

    readonly property Timer disarm: Timer {
        interval: 3000
        onTriggered: root.armed = ""
    }

    component Chip: Rectangle {
        id: chip

        property string action: ""
        property string glyph: ""
        property string caption: ""

        readonly property bool isArmed: root.armed === chip.action

        width: chip.isArmed ? name.implicitWidth + Desk.DeskTheme.capsuleHeight + 16
                            : Desk.DeskTheme.capsuleHeight
        height: Desk.DeskTheme.capsuleHeight
        radius: Desk.DeskTheme.radiusPill

        // Pure black, like the clock's chip and the greeter's buttons. Hover
        // lifts the fill and the outline stays fixed: animating
        // `islandBorder` to `hairline` passes through a brighter 50% white
        // and flashes.
        color: {
            if (chip.isArmed)
                return Desk.DeskTheme.indicatorBad
            return area.containsMouse ? Desk.DeskTheme.islandSurfaceHover : Desk.DeskTheme.island
        }
        border.width: 1
        border.color: chip.isArmed ? Desk.DeskTheme.indicatorBad : Desk.DeskTheme.islandBorder

        Behavior on width {
            NumberAnimation { duration: Desk.DeskTheme.durationFast; easing.type: Desk.DeskTheme.easing }
        }
        Behavior on color { ColorAnimation { duration: Desk.DeskTheme.durationFast } }
        Behavior on border.color { ColorAnimation { duration: Desk.DeskTheme.durationFast } }

        Row {
            anchors.centerIn: parent
            spacing: 7

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.glyph
                font.family: Desk.DeskTheme.fontMono
                font.pixelSize: 15
                color: Desk.DeskTheme.text
                opacity: chip.isArmed || area.containsMouse ? 1 : 0.75

                Behavior on opacity { NumberAnimation { duration: Desk.DeskTheme.durationFast } }
            }

            Text {
                id: name

                anchors.verticalCenter: parent.verticalCenter
                visible: chip.isArmed
                text: chip.caption
                font.family: Desk.DeskTheme.fontFamily
                font.pixelSize: Desk.DeskTheme.fontSizeSmall
                font.weight: Font.DemiBold
                color: Desk.DeskTheme.text
            }
        }

        MouseArea {
            id: area

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (chip.isArmed) {
                    root.armed = ""
                    root.disarm.stop()
                    Services.SessionService.schedule(chip.action)
                    return
                }
                root.armed = chip.action
                root.disarm.restart()
            }
        }
    }

    Chip {
        action: "reboot"
        glyph: "󰜉"
        caption: "Restart"
    }

    Chip {
        action: "shutdown"
        glyph: "󰐥"
        caption: "Shut down"
    }
}
