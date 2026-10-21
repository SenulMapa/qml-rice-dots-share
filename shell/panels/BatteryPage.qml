import QtQuick
import QtQuick.Layouts
import "../components"
import "../core"
import "../services"

Item {
    id: root

    // True only while this page is the one on screen. The carousel keeps
    // every page mounted (and visible) so this must come from the owner's
    // selection state, not from visible/opacity. Gates the Energy list.
    property bool active: false

    readonly property bool ink: Config.appearance.ink

    // Ink battery (showcase screens/system.html, battery card, 360 wide):
    // serif readout, remaining time, a three-way profile control and the
    // health, draw and capacity rows. Without ink the cards below stay.
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Math.max(0, 32 - Theme.space4)
        visible: root.ink
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 24
            spacing: 8

            Text {
                text: BatteryService.icon
                color: Theme.t1
                font.family: Config.appearance.monoFontFamily
                font.pixelSize: 18
            }
            Text {
                text: "Battery"
                color: Theme.t1
                font.family: Theme.fontUi
                font.pixelSize: 20
                font.weight: Font.DemiBold
                font.letterSpacing: -0.3
            }
        }

        RowLayout {
            Layout.topMargin: 16
            Layout.fillWidth: true
            spacing: 2

            Text {
                text: BatteryService.percentageInt
                color: Theme.t1
                font.family: Theme.fontSerif
                font.pixelSize: 96
                font.letterSpacing: -2
                lineHeight: 96
                lineHeightMode: Text.FixedHeight
            }
            Text {
                Layout.alignment: Qt.AlignBaseline
                text: "%"
                color: Theme.t2
                font.family: Theme.fontSerif
                font.pixelSize: 44
            }
        }

        RowLayout {
            Layout.topMargin: 12
            Layout.fillWidth: true
            spacing: 12

            Text {
                text: BatteryService.onBattery ? "Remaining"
                    : BatteryService.charging ? "Until full" : "Source"
                color: Theme.t2
                font.family: Theme.fontUi
                font.pixelSize: 12
            }
            Text {
                Layout.fillWidth: true
                text: BatteryService.onBattery ? BatteryService.emptyTimeLabel
                    : BatteryService.charging ? BatteryService.chargeTimeLabel
                    : BatteryService.sourceLabel
                color: Theme.t1
                elide: Text.ElideRight
                font.family: Theme.fontUi
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }
        }

        Text {
            Layout.topMargin: 32
            Layout.preferredHeight: 18
            text: "Power profile"
            color: Theme.t1
            font.family: Theme.fontUi
            font.pixelSize: 15
            font.weight: Font.DemiBold
        }

        // Three-way segmented control. Active is the Apple fill with a dark
        // glyph; inactive segments sit on the raised ink.
        Squircle {
            Layout.fillWidth: true
            Layout.topMargin: 12
            Layout.preferredHeight: 44
            radius: Theme.rCtl
            color: Theme.inkRaised

            RowLayout {
                anchors.fill: parent
                anchors.margins: 4
                spacing: 4

                Repeater {
                    model: PowerProfileService.options
                    delegate: Squircle {
                        required property var modelData
                        readonly property bool current: PowerProfileService.profileId === modelData.id
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 10
                        opacity: modelData.available ? 1 : 0.4
                        color: current ? Theme.fillOn
                            : segHover.hovered ? Theme.inkRaised2 : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: modelData.name
                            color: parent.current ? Theme.glyphOn : Theme.t2
                            font.family: Theme.fontUi
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                        HoverHandler { id: segHover }
                        TapHandler {
                            enabled: modelData.available
                            onTapped: PowerProfileService.setProfileId(modelData.id)
                        }
                    }
                }
            }
        }

        ColumnLayout {
            Layout.topMargin: 24
            Layout.fillWidth: true
            spacing: 0

            Repeater {
                model: [
                    { label: "Battery health", value: BatteryService.healthAvailable
                        ? BatteryService.healthPercentageInt + "%" : "Unavailable" },
                    { label: "Current draw", value: BatteryService.chargeRateLabel },
                    { label: "Capacity", value: BatteryService.capacityLabel }
                ]
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36

                    Text {
                        Layout.fillWidth: true
                        text: modelData.label
                        color: Theme.t2
                        font.family: Theme.fontUi
                        font.pixelSize: 13
                    }
                    Text {
                        text: modelData.value
                        color: Theme.t1
                        font.family: Theme.fontUi
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.space3
        visible: !root.ink

        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            spacing: 0

            Text {
                text: "Battery"
                color: AdaptiveColor.glassText
                font.family: Config.appearance.displayFontFamily
                font.pixelSize: Theme.textTitle + 6
                font.weight: Font.Normal
            }
            Text {
                text: "Power, endurance, and long-term health"
                color: AdaptiveColor.glassTextDim
                font.family: Config.appearance.fontFamily
                font.pixelSize: 9
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 112

            RowLayout {
                anchors.fill: parent
                anchors.margins: Theme.space4
                spacing: Theme.space4

                Text {
                    Layout.alignment: Qt.AlignVCenter
                    text: BatteryService.icon
                    color: AdaptiveColor.activeFill
                    font.family: Config.appearance.monoFontFamily
                    font.pixelSize: 44
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space1

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: BatteryService.percentageInt + "%"
                            color: AdaptiveColor.glassText
                            font.family: Config.appearance.fontFamily
                            font.pixelSize: 28
                            font.weight: Font.DemiBold
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: BatteryService.statusLabel
                            color: BatteryService.percentageInt <= 15
                                && BatteryService.onBattery
                                ? Theme.error : AdaptiveColor.glassTextDim
                            font.family: Config.appearance.fontFamily
                            font.pixelSize: Theme.textSmall
                        }
                    }

                    LevelTrack {
                        Layout.fillWidth: true
                        value: BatteryService.percentage
                        accent: BatteryService.percentageInt <= 15
                            && BatteryService.onBattery
                            ? Theme.error : AdaptiveColor.activeFill
                    }

                    Text {
                        text: BatteryService.sourceLabel + " · "
                            + BatteryService.modelLabel
                        color: AdaptiveColor.glassTextDim
                        elide: Text.ElideRight
                        font.family: Config.appearance.monoFontFamily
                        font.pixelSize: 9
                    }
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 2
            rows: 2
            columnSpacing: Theme.space3
            rowSpacing: Theme.space3

            SystemMetricCard {
                Layout.fillWidth: true
                Layout.fillHeight: true
                label: "Battery health"
                value: BatteryService.healthAvailable
                    ? BatteryService.healthPercentageInt + "%" : "Unavailable"
                valueFontSize: Theme.textSmall
                detail: BatteryService.healthLabel
                icon: "󰂑"
                accent: !BatteryService.healthAvailable ? AdaptiveColor.glassTextDim
                    : BatteryService.healthPercentageInt < 65 ? Theme.error
                    : BatteryService.healthPercentageInt < 80 ? Theme.warning
                    : Theme.success
            }

            SystemMetricCard {
                Layout.fillWidth: true
                Layout.fillHeight: true
                label: "Until charged"
                value: BatteryService.chargeTimeLabel
                valueFontSize: Theme.textSmall
                detail: BatteryService.charging
                    ? "Estimated time to full" : "Connect AC power to charge"
                icon: "󰔛"
                accent: Theme.success
            }

            SystemMetricCard {
                Layout.fillWidth: true
                Layout.fillHeight: true
                label: "Time remaining"
                value: BatteryService.emptyTimeLabel
                valueFontSize: Theme.textSmall
                detail: BatteryService.onBattery
                    ? "Estimated runtime" : "Running from external power"
                icon: "󰥔"
                accent: BatteryService.percentageInt <= 15
                    && BatteryService.onBattery ? Theme.error : AdaptiveColor.activeFill
            }

            SystemMetricCard {
                Layout.fillWidth: true
                Layout.fillHeight: true
                label: BatteryService.charging ? "Charge rate" : "Power draw"
                value: BatteryService.chargeRateLabel
                valueFontSize: Theme.textSmall
                detail: "Live battery energy rate"
                icon: "󰚥"
                accent: Theme.tertiary
            }
        }

        EnergyList {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.space4
            Layout.rightMargin: Theme.space4
            active: root.active
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 46

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.space4
                anchors.rightMargin: Theme.space4
                spacing: Theme.space3

                Text {
                    text: "󰁹"
                    color: Theme.secondary
                    font.family: Config.appearance.monoFontFamily
                    font.pixelSize: 13
                }
                Text {
                    text: "Current capacity"
                    color: AdaptiveColor.glassTextDim
                    font.family: Config.appearance.fontFamily
                    font.pixelSize: Theme.textSmall
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: BatteryService.capacityLabel
                    color: AdaptiveColor.glassText
                    font.family: Config.appearance.monoFontFamily
                    font.pixelSize: Theme.textSmall
                    font.weight: Font.DemiBold
                }
            }
        }
    }
}
