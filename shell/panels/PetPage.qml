import QtQuick
import QtQuick.Layouts
import "../core"
import "../components"
import "../services"
import "../desktop/services" as DeskServices

/**
 * PetPage — blob sub-page: active pet, level/XP, mood, feed/play actions.
 * Renders desktop/services/DeskPetService state.
 * Esc/back() morphs back to dashboard.
 */
Item {
    id: root

    signal back()

    property real availableWidth: 400
    property real availableHeight: 400

    readonly property real pageWidth: Math.min(Theme.u(16), availableWidth - Theme.u(2))
    readonly property real pageHeight: Math.min(Theme.u(10), availableHeight * 0.7)

    Keys.onEscapePressed: root.back()

    // Ink (Config.appearance.ink): Geist title and pet name, t1/t2/t3 text,
    // monochrome fillOn XP bar on an inkRaised2 track. Old branches stay for
    // ink off.
    readonly property bool ink: Config.appearance.ink

    Component.onCompleted: DeskServices.DeskPetService.subscribe()
    Component.onDestruction: DeskServices.DeskPetService.release()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.space2
        spacing: Theme.space2

        // Header
        Text {
            Layout.fillWidth: true
            text: "Pet"
            color: root.ink ? Theme.t1 : AdaptiveColor.glassText
            font.family: root.ink ? Theme.fontUi : Config.appearance.handFontFamily
            font.pixelSize: root.ink ? 20 : Theme.dashTitle
            font.weight: root.ink ? Font.DemiBold : Font.Normal
            style: root.ink ? Text.Normal : Text.Outline
            styleColor: AdaptiveColor.glassText
        }

        Item { Layout.fillHeight: true }

        // Pet name or "Egg"
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: DeskServices.DeskPetService.titleOf(DeskServices.DeskPetService.pet)
            color: root.ink ? Theme.t1 : AdaptiveColor.activeFill
            font.family: root.ink ? Theme.fontUi : Config.appearance.handFontFamily
            font.pixelSize: root.ink ? 20 : Theme.dashLabel
            font.weight: root.ink ? Font.DemiBold : Font.Normal
        }

        // Mood line
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: DeskServices.DeskPetService.moodLine
            color: root.ink ? Theme.t2 : AdaptiveColor.glassTextDim
            font.pixelSize: root.ink ? 13 : Theme.dashCaption
            Binding on font.family { when: root.ink; value: Theme.fontUi }
        }

        Item { Layout.preferredHeight: Theme.space2 }

        // Level and XP bar
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.space1

            RowLayout {
                Text {
                    text: "Level " + DeskServices.DeskPetService.level
                    color: root.ink ? Theme.t1 : AdaptiveColor.glassText
                    font.pixelSize: root.ink ? 13 : Theme.dashCaption
                    Binding on font.family { when: root.ink; value: Theme.fontUi }
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: DeskServices.DeskPetService.xp + "/"
                        + DeskServices.DeskPetService.threshold
                    color: root.ink ? Theme.t3 : AdaptiveColor.glassTextDim
                    font.pixelSize: root.ink ? 12 : Theme.dashCaption
                    Binding on font.family { when: root.ink; value: Theme.fontUi }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 4
                radius: 2
                color: root.ink ? Theme.inkRaised2 : Qt.alpha(AdaptiveColor.activeFill, 0.1)

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * DeskServices.DeskPetService.progress
                    radius: 2
                    color: root.ink ? Theme.fillOn : AdaptiveColor.activeFill
                }
            }
        }

        // Egg progress (milestones)
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.space1
            visible: !DeskServices.DeskPetService.complete

            RowLayout {
                Text {
                    text: "Next egg in"
                    color: root.ink ? Theme.t1 : AdaptiveColor.glassText
                    font.pixelSize: root.ink ? 13 : Theme.dashCaption
                    Binding on font.family { when: root.ink; value: Theme.fontUi }
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: DeskServices.DeskPetService.levelsToNextEgg + " levels"
                    color: root.ink ? Theme.t3 : AdaptiveColor.glassTextDim
                    font.pixelSize: root.ink ? 12 : Theme.dashCaption
                    Binding on font.family { when: root.ink; value: Theme.fontUi }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 4
                radius: 2
                color: root.ink ? Theme.inkRaised2 : Qt.alpha(Theme.success, 0.1)

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * DeskServices.DeskPetService.eggProgress
                    radius: 2
                    color: Theme.success
                }
            }
        }

        Item { Layout.fillHeight: true }

        // Action buttons: Feed, Play -- glass capsules (glass redesign).
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            GlassPillButton {
                Layout.fillWidth: true
                icon: "restaurant"
                text: "Feed"
                prominent: DeskServices.DeskPetService.canFeed
                available: DeskServices.DeskPetService.canFeed
                onClicked: DeskServices.DeskPetService.feed()
            }
            GlassPillButton {
                Layout.fillWidth: true
                icon: "sports_esports"
                text: "Play"
                available: DeskServices.DeskPetService.canPlay
                onClicked: DeskServices.DeskPetService.play()
            }
        }

        GlassPillButton {
            Layout.alignment: Qt.AlignHCenter
            implicitHeight: 32
            icon: "arrow_back"
            text: "Back"
            onClicked: root.back()
        }
    }
}
