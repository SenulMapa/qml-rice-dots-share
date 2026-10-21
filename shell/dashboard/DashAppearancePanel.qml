// Simplified port of impasto's bar/island/AppearancePanel.qml
// (github.com/andreumassanet/impasto, GPL-3.0, Andreu Massanet).
//
// Upstream's AppearancePanel picks a whole named palette plus wallpaper/
// accent options this shell doesn't have a matching concept for (its theme
// IS the adaptive wallpaper palette -- see DashControls/AppearanceCard.qml's
// header). This panel is the fuller settings surface over the same real
// DeskSettings properties the desktop port already persists: desktop clock
// theme/style, clock format/seconds, the deck's empty-workspace behaviour,
// and the GitHub username the desktop GitHub face reads.

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../desktop/services" as Desk
import "components" as DashComponents
import "../components"

ColumnLayout {
    id: root

    signal closed()

    spacing: 14

    DashComponents.Card {
        Layout.fillWidth: true
        padding: 12

        ColumnLayout {
            anchors.fill: parent
            spacing: 8

            Text {
                text: "Desktop clock"
                font.family: Desk.DeskTheme.fontFamily
                font.pixelSize: Desk.DeskTheme.fontSizeLabel
                color: Desk.DeskTheme.textMuted
            }

            RowLayout {
                spacing: 6
                Repeater {
                    model: [{ id: "modern", label: "Modern" }, { id: "analogue", label: "Analogue" }]
                    DashComponents.QuickTile {
                        required property var modelData
                        Layout.preferredWidth: 120
                        Layout.preferredHeight: 40
                        label: modelData.label
                        active: Desk.DeskSettings.desktopTheme === modelData.id
                        onToggled: Desk.DeskSettings.set("desktopTheme", modelData.id)
                    }
                }
            }

            RowLayout {
                spacing: 6
                DashComponents.QuickTile {
                    Layout.preferredWidth: 160
                    Layout.preferredHeight: 40
                    label: "Show seconds"
                    active: Desk.DeskSettings.clockShowsSeconds
                    onToggled: Desk.DeskSettings.set("clockShowsSeconds", !Desk.DeskSettings.clockShowsSeconds)
                }
                DashComponents.QuickTile {
                    Layout.preferredWidth: 160
                    Layout.preferredHeight: 40
                    label: "Hide deck when empty"
                    active: Desk.DeskSettings.deckOnEmpty
                    onToggled: Desk.DeskSettings.set("deckOnEmpty", !Desk.DeskSettings.deckOnEmpty)
                }
            }
        }
    }

    DashComponents.Card {
        Layout.fillWidth: true
        padding: 12

        ColumnLayout {
            anchors.fill: parent
            spacing: 8

            Text {
                text: "Widget style"
                font.family: Desk.DeskTheme.fontFamily
                font.pixelSize: Desk.DeskTheme.fontSizeLabel
                color: Desk.DeskTheme.textMuted
            }

            RowLayout {
                spacing: 6
                Repeater {
                    model: ["capsule", "outline", "bare", "accent"]
                    DashComponents.QuickTile {
                        required property string modelData
                        Layout.preferredWidth: 90
                        Layout.preferredHeight: 40
                        label: modelData
                        active: Desk.DeskSettings.desktopStyle === modelData
                        onToggled: Desk.DeskSettings.set("desktopStyle", modelData)
                    }
                }
            }
        }
    }

    DashComponents.Card {
        Layout.fillWidth: true
        padding: 12

        ColumnLayout {
            anchors.fill: parent
            spacing: 8

            Text {
                text: "GitHub contributions"
                font.family: Desk.DeskTheme.fontFamily
                font.pixelSize: Desk.DeskTheme.fontSizeLabel
                color: Desk.DeskTheme.textMuted
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                TextField {
                    id: userField
                    Layout.fillWidth: true
                    placeholderText: "GitHub username"
                    text: Desk.DeskSettings.githubUser
                    color: Desk.DeskTheme.text
                    font.family: Desk.DeskTheme.fontFamily
                    onEditingFinished: Desk.DeskSettings.set("githubUser", text)
                    background: Squircle {
                        radius: Desk.DeskTheme.radiusSmall
                        color: Desk.DeskTheme.islandSurfaceHover
                        borderColor: Desk.DeskTheme.islandBorder
                        borderWidth: 1
                    }
                }
            }
        }
    }

    Item { Layout.fillHeight: true }
}
