// Simplified port of impasto's bar/island/OverviewPanel.qml
// (github.com/andreumassanet/impasto, GPL-3.0, Andreu Massanet).
//
// Upstream draws a live ScreencopyView thumbnail of every window on every
// workspace, scaled to the real monitor layout. That capture pipeline was
// not ported in this run (time-boxed scope reduction -- see HANDOVER.md);
// this panel keeps the workspace GRID and real window COUNTS
// (services/HyprlandService.qml, already the shell's own), just without
// live pixel previews inside each cell. Clicking a cell still really
// switches workspace.

import QtQuick
import QtQuick.Layouts
import "../desktop/services" as Desk
import "../services" as Shell
import "../core" as Core
import "../components"

ColumnLayout {
    id: root

    signal closed()

    readonly property int columns: Math.min(5, Core.Config.hyprland.workspaceCount)
    readonly property int workspaceCount: Core.Config.hyprland.workspaceCount

    spacing: 10

    Text {
        text: "Workspaces"
        font.family: Desk.DeskTheme.fontFamily
        font.pixelSize: Desk.DeskTheme.fontSizeSmall
        font.weight: Font.DemiBold
        color: Desk.DeskTheme.text
    }

    GridLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        columns: root.columns
        rowSpacing: 8
        columnSpacing: 8

        Repeater {
            model: root.workspaceCount

            Squircle {
                required property int index
                readonly property int workspaceId: index + 1
                readonly property var workspace: Shell.HyprlandService.workspaceById(workspaceId)
                readonly property bool occupied: workspace !== null && workspace !== undefined
                readonly property bool focused: Shell.HyprlandService.activeWorkspaceId === workspaceId

                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: 60
                radius: Desk.DeskTheme.radiusMedium
                color: focused ? Desk.DeskTheme.accent
                    : (cellMouse.containsMouse ? Desk.DeskTheme.islandSurfaceHover : Desk.DeskTheme.islandSurface)
                borderColor: occupied ? Desk.DeskTheme.islandBorder : "transparent"
                borderWidth: 1

                Behavior on color { ColorAnimation { duration: Desk.DeskTheme.durationFast } }

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 2

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: workspaceId
                        font.family: Desk.DeskTheme.fontFamily
                        font.pixelSize: Desk.DeskTheme.fontSizeMedium
                        font.weight: Font.DemiBold
                        color: focused ? Desk.DeskTheme.accentText : Desk.DeskTheme.text
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        visible: occupied
                        text: Shell.HyprlandService.workspaceWindowCount(workspace) + " win"
                        font.family: Desk.DeskTheme.fontMono
                        font.pixelSize: Desk.DeskTheme.fontSizeLabel
                        color: focused ? Desk.DeskTheme.accentText : Desk.DeskTheme.textMuted
                    }
                }

                MouseArea {
                    id: cellMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Shell.HyprlandService.activateWorkspace(workspaceId)
                        root.closed()
                    }
                }
            }
        }
    }
}
