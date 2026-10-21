import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import "../core"
import "../services"

// Self-contained audio satellite content for the blob.
// Displays output/input volume controls and device lists.
Item {
    id: root

    readonly property real maxHeight: Theme.u(9.5)
    readonly property real chromeHeight: Theme.u(0.35) * 2
        + headerTitle.implicitHeight + Theme.u(0.2)
        + (Theme.u(1.2) * 2 + Theme.u(0.2) * 2)  // two level controls
    readonly property real rowsCap: Math.max(Theme.u(1.6), maxHeight - chromeHeight)

    readonly property int contentHeight: Math.round(mainColumn.implicitHeight
        + Theme.u(0.35) * 2)

    ColumnLayout {
        id: mainColumn
        anchors.fill: parent
        anchors.topMargin: Theme.u(0.35)
        anchors.bottomMargin: Theme.u(0.35)
        anchors.leftMargin: Theme.u(0.35)
        anchors.rightMargin: Theme.u(0.35)
        spacing: Theme.u(0.2)

        // Header
        Text {
            id: headerTitle
            Layout.fillWidth: true
            text: "Audio"
            color: Config.appearance.ink ? Theme.t1 : AdaptiveColor.glassText
            font.family: Config.appearance.ink ? Theme.fontUi : Config.appearance.displayFontFamily
            font.pixelSize: Config.appearance.ink ? 20 : Theme.u(0.58)
            font.weight: Config.appearance.ink ? Font.DemiBold : Font.Normal
            font.letterSpacing: Config.appearance.ink ? -0.3 : 0
        }

        // Output volume slider
        LevelControl {
            Layout.fillWidth: true
            Layout.preferredHeight: Config.appearance.ink ? 44 : Theme.u(1.2)
            visible: AudioService.available
            icon: AudioService.muted ? "󰝟" : "󰕾"
            iconName: AudioService.muted ? "volume-x" : "volume-2"
            level: AudioService.volume
            available: AudioService.available
            onLevelRequested: level => AudioService.setVolume(Math.round(level * 100))
            onActionRequested: AudioService.toggleMute()
        }

        // Input volume slider
        LevelControl {
            Layout.fillWidth: true
            Layout.preferredHeight: Config.appearance.ink ? 44 : Theme.u(1.2)
            visible: AudioService.microphoneAvailable
            icon: AudioService.microphoneMuted ? "󰍭" : "󰍬"
            iconName: AudioService.microphoneMuted ? "mic-off" : "mic"
            level: AudioService.microphoneVolume
            available: AudioService.microphoneAvailable
            onLevelRequested: level => AudioService.setMicrophoneVolume(Math.round(level * 100))
            onActionRequested: AudioService.toggleMicrophoneMute()
        }

        // Rows container with scrolling
        Item {
            id: rowsArea
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(rowsColumn.implicitHeight, root.rowsCap)

            Flickable {
                id: rowsScroll
                anchors.fill: parent
                contentWidth: width
                contentHeight: rowsColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: rowsColumn
                    width: rowsScroll.width
                    spacing: Theme.u(0.3)

                    // Output section header
                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.u(0.1)
                        visible: AudioService.outputDevices.length > 0
                        text: Config.appearance.ink ? "Output" : "OUTPUT"
                        color: Config.appearance.ink ? Theme.t3 : Theme.outline
                        font.family: Config.appearance.ink ? Theme.fontUi : Config.appearance.monoFontFamily
                        font.pixelSize: Config.appearance.ink ? 12 : Theme.u(0.26)
                        font.weight: Config.appearance.ink ? Font.Medium : Font.Normal
                        font.letterSpacing: Config.appearance.ink ? 0 : Theme.u(0.26) * 0.1
                    }

                    // Output devices list
                    Repeater {
                        model: AudioService.outputDevices

                        delegate: Squircle {
                            required property var modelData
                            readonly property bool current: AudioService.sink === modelData

                            Layout.fillWidth: true
                            implicitHeight: Config.appearance.ink ? 44
                                : deviceContent.implicitHeight + Theme.u(0.25) * 2
                            radius: Config.appearance.ink ? Theme.rCtl : Theme.u(0.34)
                            color: Config.appearance.ink
                                ? (current ? Theme.inkRaised : Qt.rgba(0, 0, 0, 0))
                                : deviceHover.hovered
                                    ? Qt.alpha(AdaptiveColor.glassTextDim, 0.08) : "transparent"

                            RowLayout {
                                id: deviceContent
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: Theme.u(0.3)
                                anchors.rightMargin: Theme.u(0.3)
                                spacing: Theme.u(0.3)

                                Text {
                                    text: "󰕾"
                                    color: AdaptiveColor.glassText
                                    font.family: Config.appearance.monoFontFamily
                                    font.pixelSize: Theme.u(0.4)
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Text {
                                        Layout.fillWidth: true
                                        text: AudioService.displayName(modelData, "Unknown")
                                        color: Config.appearance.ink ? Theme.t1
                                            : AudioService.sink === modelData
                                            ? AdaptiveColor.activeFill : AdaptiveColor.glassText
                                        elide: Text.ElideRight
                                        font.family: Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily
                                        font.pixelSize: Config.appearance.ink ? 13 : Theme.u(0.36)
                                        font.weight: Config.appearance.ink ? Font.DemiBold : Font.Medium
                                    }
                                }

                                Text {
                                    visible: AudioService.sink === modelData
                                    text: "󰄬"
                                    color: Config.appearance.ink ? Theme.t1 : AdaptiveColor.activeFill
                                    font.family: Config.appearance.monoFontFamily
                                    font.pixelSize: Theme.u(0.32)
                                }
                            }

                            HoverHandler { id: deviceHover }
                            TapHandler {
                                enabled: true
                                onTapped: AudioService.setOutputDevice(modelData)
                            }

                            Behavior on color { ColorAnimation { duration: 100 } }
                        }
                    }

                    // Input section header
                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.u(0.1)
                        visible: AudioService.inputDevices.length > 0
                        text: Config.appearance.ink ? "Input" : "INPUT"
                        color: Config.appearance.ink ? Theme.t3 : Theme.outline
                        font.family: Config.appearance.ink ? Theme.fontUi : Config.appearance.monoFontFamily
                        font.pixelSize: Config.appearance.ink ? 12 : Theme.u(0.26)
                        font.weight: Config.appearance.ink ? Font.Medium : Font.Normal
                        font.letterSpacing: Config.appearance.ink ? 0 : Theme.u(0.26) * 0.1
                    }

                    // Input devices list
                    Repeater {
                        model: AudioService.inputDevices

                        delegate: Squircle {
                            required property var modelData
                            readonly property bool current: AudioService.source === modelData

                            Layout.fillWidth: true
                            implicitHeight: Config.appearance.ink ? 44
                                : inputContent.implicitHeight + Theme.u(0.25) * 2
                            radius: Config.appearance.ink ? Theme.rCtl : Theme.u(0.34)
                            color: Config.appearance.ink
                                ? (current ? Theme.inkRaised : Qt.rgba(0, 0, 0, 0))
                                : inputHover.hovered
                                    ? Qt.alpha(AdaptiveColor.glassTextDim, 0.08) : "transparent"

                            RowLayout {
                                id: inputContent
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: Theme.u(0.3)
                                anchors.rightMargin: Theme.u(0.3)
                                spacing: Theme.u(0.3)

                                Text {
                                    text: "󰍬"
                                    color: AdaptiveColor.glassText
                                    font.family: Config.appearance.monoFontFamily
                                    font.pixelSize: Theme.u(0.4)
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Text {
                                        Layout.fillWidth: true
                                        text: AudioService.displayName(modelData, "Unknown")
                                        color: Config.appearance.ink ? Theme.t1
                                            : AudioService.source === modelData
                                            ? AdaptiveColor.activeFill : AdaptiveColor.glassText
                                        elide: Text.ElideRight
                                        font.family: Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily
                                        font.pixelSize: Config.appearance.ink ? 13 : Theme.u(0.36)
                                        font.weight: Config.appearance.ink ? Font.DemiBold : Font.Medium
                                    }
                                }

                                Text {
                                    visible: AudioService.source === modelData
                                    text: "󰄬"
                                    color: Config.appearance.ink ? Theme.t1 : AdaptiveColor.activeFill
                                    font.family: Config.appearance.monoFontFamily
                                    font.pixelSize: Theme.u(0.32)
                                }
                            }

                            HoverHandler { id: inputHover }
                            TapHandler {
                                enabled: true
                                onTapped: AudioService.setInputDevice(modelData)
                            }

                            Behavior on color { ColorAnimation { duration: 100 } }
                        }
                    }
                    // Apps: per-app playback volume (ink only). Hidden when
                    // there are no playback streams.
                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.u(0.1)
                        visible: Config.appearance.ink && AudioService.playbackStreams.length > 0
                        text: "Apps"
                        color: Theme.t3
                        font.family: Theme.fontUi
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }
                    Repeater {
                        model: Config.appearance.ink ? AudioService.playbackStreams : []

                        delegate: RowLayout {
                            id: appRow
                            required property var modelData
                            readonly property real level: Math.max(0, Math.min(1,
                                modelData?.audio?.volume ?? 0))

                            Layout.fillWidth: true
                            Layout.preferredHeight: 44
                            spacing: 12

                            Text {
                                Layout.preferredWidth: 76
                                Layout.maximumWidth: 76
                                text: AudioService.streamName(appRow.modelData)
                                color: Theme.t1
                                elide: Text.ElideRight
                                font.family: Theme.fontUi
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                            }

                            // 6px track: inkRaised, fillOn fill, round caps.
                            Item {
                                id: appTrack
                                Layout.fillWidth: true
                                Layout.preferredHeight: 44

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: 6
                                    radius: 3
                                    color: Theme.inkRaised
                                }
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width * appRow.level
                                    height: 6
                                    radius: 3
                                    color: Theme.fillOn
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    function setFrom(mx): void {
                                        AudioService.setStreamVolume(appRow.modelData, mx / width)
                                    }
                                    onPressed: mouse => setFrom(mouse.x)
                                    onPositionChanged: mouse => {
                                        if (pressed)
                                            setFrom(mouse.x)
                                    }
                                }
                            }

                            Text {
                                Layout.preferredWidth: 40
                                Layout.maximumWidth: 40
                                horizontalAlignment: Text.AlignRight
                                text: Math.round(appRow.level * 100)
                                color: Theme.t1
                                font.family: Theme.fontSerif
                                font.pixelSize: 20
                            }
                        }
                    }
                }
            }

            // Empty state
            Text {
                anchors.centerIn: parent
                visible: AudioService.outputDevices.length === 0
                    && AudioService.inputDevices.length === 0
                text: "No audio devices found"
                color: Config.appearance.ink ? Theme.t2 : AdaptiveColor.glassTextDim
                font.family: Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily
                font.pixelSize: Theme.u(0.28)
            }
        }
    }

    // Track Pipewire objects to ensure audio properties are valid
    property PwObjectTracker nodeTracker: PwObjectTracker {
        objects: Pipewire.nodes.values.filter(node => node?.audio && !node.isStream)
    }
}
