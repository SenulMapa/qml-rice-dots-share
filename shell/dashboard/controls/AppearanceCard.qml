// Simplified port of impasto's bar/island/controls/AppearanceCard.qml
// (github.com/andreumassanet/impasto, GPL-3.0, Andreu Massanet).
//
// Upstream lets you pick a whole named palette (ThemeService). This shell's
// theme is the adaptive wallpaper palette (core/Theme, forwarded by
// DeskTheme) -- there is no fixed palette list to swap between. What DOES
// stay a real, per-user setting from the desktop port is desktop widget
// theme/style (DeskSettings.desktopTheme/desktopStyle), so this card
// exposes those instead of fabricating a palette picker with nothing real
// behind it.

import QtQuick
import QtQuick.Layouts
import "../../desktop/services" as Desk
import "../../desktop/components" as DeskComponents
import "../components" as DashComponents

DashComponents.Card {
    id: root
    padding: 12
    property int cols: 2
    property int rows: 2

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

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

                DeskComponents.PillButton {
                    required property var modelData
                    text: modelData.label
                    active: Desk.DeskSettings.desktopTheme === modelData.id
                    onClicked: Desk.DeskSettings.set("desktopTheme", modelData.id)
                }
            }
        }

        Text {
            text: "Widget style"
            Layout.topMargin: 4
            font.family: Desk.DeskTheme.fontFamily
            font.pixelSize: Desk.DeskTheme.fontSizeLabel
            color: Desk.DeskTheme.textMuted
        }

        RowLayout {
            spacing: 6

            Repeater {
                model: ["capsule", "outline", "bare", "accent"]

                DeskComponents.PillButton {
                    required property string modelData
                    text: modelData
                    active: Desk.DeskSettings.desktopStyle === modelData
                    onClicked: Desk.DeskSettings.set("desktopStyle", modelData)
                }
            }
        }
    }
}
