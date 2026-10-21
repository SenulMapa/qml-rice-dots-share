import QtQuick
import QtQuick.Layouts
import "../core"
import "../components"
import "../services"

Item {
    id: root

    property string selectedPage: "weather"
    signal pageRequested(string page)

    readonly property var pages: [
        { id: "weather", label: "Weather", icon: "󰖐" },
        { id: "calendar", label: "Calendar", icon: "󰃭" },
        { id: "media-center", label: "Media", icon: "󰎆" },
        { id: "system", label: "System", icon: "󰍛" },
        { id: "battery", label: "Battery", icon: "󰁹" }
    ]
    readonly property int pageIndex: Math.max(0,
        pages.findIndex(option => option.id === selectedPage))

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.space2

        Item {
            id: tabBar
            Layout.fillWidth: true
            Layout.preferredHeight: 38

            RowLayout {
                id: tabRow
                anchors.fill: parent
                spacing: 3

                Repeater {
                    id: tabRepeater
                    model: root.pages
                    delegate: Squircle {
                        required property var modelData
                        readonly property bool selected:
                            modelData.id === root.selectedPage
                        visible: modelData.id !== "battery"
                            || BatteryService.available
                        Layout.fillWidth: visible
                        Layout.fillHeight: true
                        radius: Theme.radiusSmall
                        // No fill for the selected tab any more -- the Bead
                        // bar underline (below) IS the selection signal, so
                        // this only carries the faint hover wash.
                        color: tabHover.hovered
                            ? Qt.alpha(AdaptiveColor.glassText, 0.05) : "transparent"

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: Theme.space1
                            Text {
                                text: modelData.icon
                                color: selected ? AdaptiveColor.activeFill
                                    : AdaptiveColor.glassTextDim
                                font.family: Config.appearance.monoFontFamily
                                font.pixelSize: 12
                            }
                            Text {
                                text: modelData.label
                                color: selected ? AdaptiveColor.activeFill
                                    : AdaptiveColor.glassTextDim
                                font.family: Config.appearance.fontFamily
                                font.pixelSize: 10
                                font.weight: selected ? Font.DemiBold : Font.Medium
                            }
                        }

                        HoverHandler { id: tabHover }
                        TapHandler { onTapped: root.pageRequested(modelData.id) }
                        Behavior on color {
                            ColorAnimation { duration: Animations.fast }
                        }
                    }
                }
            }

            // Selection bead: a short bar tracking the selected tab's
            // centre, riding just under the row. tabRepeater's index order
            // matches root.pages/root.pageIndex exactly (same model).
            Bead {
                form: "bar"
                color: AdaptiveColor.activeFill
                dotSize: Theme.u(0.13)
                target: {
                    const item = tabRepeater.count > root.pageIndex
                        ? tabRepeater.itemAt(root.pageIndex) : null
                    return Qt.point(item ? item.x + item.width / 2 : 0,
                        tabBar.height - Theme.u(0.05))
                }
            }
        }

        // Directional carousel: all five pages live side by side in one
        // Row, and a single spring drives the strip's x -- a tab to the
        // right slides the strip left (that page arrives from the right)
        // and vice-versa, with the strip's own velocity driving a short
        // fade dip (fastest mid-transition, back to full at rest) instead
        // of a fixed-duration clip. Pages stay mounted the whole time (same
        // as the StackLayout this replaces), so their services/state never
        // reset on a tab switch.
        Item {
            id: pageContent
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            Row {
                id: pageStrip
                x: -stripX.value
                height: pageContent.height
                opacity: Math.max(0.5, fade.value)

                WeatherPage { width: pageContent.width; height: pageContent.height }
                CalendarPage { width: pageContent.width; height: pageContent.height }
                MediaPage { width: pageContent.width; height: pageContent.height }
                SystemPage { width: pageContent.width; height: pageContent.height }
                BatteryPage {
                    width: pageContent.width
                    height: pageContent.height
                    active: root.selectedPage === "battery" && root.visible
                }
            }

            MotionValue {
                id: stripX
                unit: "px"
                omega: Motion.omegaEnter
                zeta: Motion.zetaEnter
                target: root.pageIndex * pageContent.width
            }
            MotionValue {
                id: fade
                unit: "ratio"
                omega: Motion.omegaEnter * 1.6
                zeta: 1.0
                target: stripX.active ? 0.5 : 1
            }
        }
    }

    Connections {
        target: BatteryService
        function onAvailableChanged(): void {
            if (!BatteryService.available && root.selectedPage === "battery")
                root.pageRequested("weather")
        }
    }
}
