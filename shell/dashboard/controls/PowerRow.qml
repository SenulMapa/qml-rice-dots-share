// Ported from impasto's bar/island/controls/PowerRow.qml
// (github.com/andreumassanet/impasto, GPL-3.0, Andreu Massanet).
//
// Built from a real session-action list, so an action is a row of data.
// Actions that end the session arm on the first click (red, labelled) and
// run on the second. Lock and suspend run at once.
//
// Adaptation: upstream's own SessionService.actions/.run() ->
// DashControlsService.powerActions (wraps the shell's real SessionService,
// out of scope to duplicate per the brief) / DashControlsService.runPower().
// "destructive" here is derived locally (logout/reboot/shutdown) since the
// shell's SessionService doesn't tag actions with that flag itself.

import QtQuick
import QtQuick.Layouts
import "../../desktop/services" as Desk
import "../services" as DashServices
import "../../components"

RowLayout {
    id: root

    property string armed: ""

    signal ran(string action)

    spacing: 4

    readonly property var destructiveIds: ["logout", "reboot", "shutdown"]

    readonly property Timer disarm: Timer {
        interval: 3000
        onTriggered: root.armed = ""
    }

    Repeater {
        model: DashServices.DashControlsService.powerActions.filter(a => a.available)

        Squircle {
            id: button

            required property var modelData
            readonly property bool isArmed: root.armed === button.modelData.id
            readonly property bool destructive: root.destructiveIds.includes(button.modelData.id)

            Layout.preferredWidth: button.isArmed ? label.implicitWidth + 34 : 32
            Layout.preferredHeight: 28
            radius: Desk.DeskTheme.radiusSmall

            color: {
                if (button.isArmed)
                    return Desk.DeskTheme.red
                return mouse.containsMouse ? Desk.DeskTheme.islandSurfaceHover : "transparent"
            }
            borderColor: button.isArmed ? Desk.DeskTheme.red
                : (mouse.containsMouse ? Desk.DeskTheme.islandBorder : "transparent")
            borderWidth: 1

            Behavior on Layout.preferredWidth {
                NumberAnimation { duration: Desk.DeskTheme.durationFast; easing.type: Desk.DeskTheme.easing }
            }
            Behavior on color { ColorAnimation { duration: Desk.DeskTheme.durationFast } }

            RowLayout {
                anchors.centerIn: parent
                spacing: 6

                Text {
                    text: button.modelData.icon
                    font.family: Desk.DeskTheme.fontMono
                    font.pixelSize: 14
                    color: {
                        if (button.isArmed)
                            return Desk.DeskTheme.accentText
                        return mouse.containsMouse ? Desk.DeskTheme.accent : Desk.DeskTheme.text
                    }
                }

                Text {
                    id: label
                    visible: button.isArmed
                    text: button.modelData.label
                    font.family: Desk.DeskTheme.fontFamily
                    font.pixelSize: Desk.DeskTheme.fontSizeSmall
                    font.weight: Font.DemiBold
                    color: Desk.DeskTheme.accentText
                }
            }

            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (!button.destructive || button.isArmed) {
                        root.armed = ""
                        root.disarm.stop()
                        DashServices.DashControlsService.runPower(button.modelData.id)
                        root.ran(button.modelData.id)
                        return
                    }
                    root.armed = button.modelData.id
                    root.disarm.restart()
                }
            }
        }
    }
}
