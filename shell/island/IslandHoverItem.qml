import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import "../components"
import "../core"
import "../services"

Item {
    id: root
    required property string itemId
    property var monitor
    // A mouse user's only path into the control centre without the (removed)
    // island tab strip: the status cluster's own Wi-Fi/battery icons open it
    // directly, the same page a click on the resting pill's power icon opens.
    readonly property bool opensControlCenter: itemId === "Network"
        || itemId === "Battery" || itemId === "Bluetooth" || itemId === "Clock"
    // `card` is the impasto card page this item corresponds to
    // (DeskSettings.islandImpastoCards -- island/Island.qml's
    // `onControlCenterRequested` decides whether to honour it or fall back
    // to the plain dashboard open), empty for anything with no dedicated
    // card page yet. Clock opens the calendar card directly, same entry
    // point island/IslandRestItem.qml's own clock face wires on the
    // resting pill.
    readonly property string card: itemId === "Network" ? "wifi"
        : itemId === "Bluetooth" ? "bluetooth"
        : itemId === "Battery" ? "battery"
        : itemId === "Clock" ? "calendar" : ""
    signal controlCenterRequested(string card)
    readonly property bool available: itemId === "Media" ? MediaService.hoverVisible
        : itemId === "Network" ? NetworkService.available
        : itemId === "Bluetooth" ? BluetoothService.available
        : itemId === "Battery" ? BatteryService.available : true
    implicitWidth: itemId === "Workspaces" ? Math.round(54 * Math.max(1,
            Config.island.hoverIconScale))
        : itemId === "Clock" ? Math.round(90 * Math.max(1,
            Config.island.hoverTextScale))
        : itemId === "Media" ? Math.round(90 * Math.max(1,
            Config.island.hoverTextScale))
        : itemId === "Audio" || itemId === "Network"
            ? Math.round(42 * Config.island.hoverContentScale)
        : itemId === "Battery" ? Math.round(48 * Config.island.hoverContentScale)
        : itemId === "Dnd" && NotificationService.count > 0
            ? Math.round(18 * Config.island.hoverContentScale)
        : Math.round(24 * Config.island.hoverContentScale)
    readonly property real minimumWidth: itemId === "Workspaces"
        ? Math.round(56 * Config.island.hoverIconScale)
        : itemId === "Clock"
            ? Math.round(88 * Config.island.hoverTextScale)
        : itemId === "Media"
            ? Math.round(94 * Config.island.hoverContentScale)
        : itemId === "Audio" || itemId === "Network"
            ? Math.round(38 * Config.island.hoverContentScale)
        : itemId === "Battery"
            ? Math.round(44 * Config.island.hoverContentScale)
        : itemId === "Dnd" && NotificationService.count > 0
            ? Math.round(18 * Config.island.hoverContentScale)
        : Math.round(22 * Config.island.hoverContentScale)
    implicitHeight: Config.island.hoverHeight
    visible: available

    Loader {
        anchors.fill: parent
        sourceComponent: root.itemId === "Workspaces" ? workspacesComponent
            : root.itemId === "Clock" ? clockComponent
            : root.itemId === "Media" ? mediaComponent
            : root.itemId === "Audio" ? audioComponent
            : root.itemId === "Network" ? networkComponent
            : root.itemId === "Dnd" ? dndComponent
            : root.itemId === "Bluetooth" ? bluetoothComponent
            : root.itemId === "KeepAwake" ? keepAwakeComponent
            : root.itemId === "Battery" ? batteryComponent : null
    }

    Component {
        id: workspacesComponent
        Item {
            RowLayout {
                anchors.centerIn: parent
                spacing: Theme.space1
                Repeater {
                    model: 5
                    StatusDot {
                        active: root.monitor?.activeWorkspace?.id === index + 1
                        occupied: HyprlandService.occupiedWorkspaces.some(
                            workspace => workspace.id === index + 1)
                        urgent: HyprlandService.urgentWorkspaces.some(
                            workspace => workspace.id === index + 1)
                    }
                }
            }
        }
    }

    Component {
        id: clockComponent
        Item {
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 0
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: ShellState.time
                    color: AdaptiveColor.glassText
                    font.family: Config.appearance.clockFontFamily
                    font.features: ({ "tnum": 1 })
                    // 20px in the owner's Figma (node 4:2) -- Theme.u(0.45).
                    // Theme.u() already carries DisplayScale.primary and so
                    // does hoverTextScale now (core/Config.qml) -- divide the
                    // latter back out so this doesn't double-scale.
                    font.pixelSize: Math.round(Theme.u(0.45)
                        * (Config.island.hoverTextScale / DisplayScale.primary))
                    font.weight: Font.DemiBold
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: ShellState.dateLabel
                    color: AdaptiveColor.glassTextDim
                    font.family: Config.appearance.fontFamily
                    // 10px in the owner's Figma (node 4:2) -- Theme.u(0.23).
                    // Same double-scale note as above.
                    font.pixelSize: Math.round(Theme.u(0.23)
                        * (Config.island.hoverTextScale / DisplayScale.primary))
                }
            }
        }
    }

    Component {
        id: mediaComponent
        Item {
            RowLayout {
                anchors.fill: parent
                spacing: Theme.space2
                ClippingRectangle {
                    Layout.preferredWidth: Math.round(30
                        * Config.island.hoverIconScale)
                    Layout.preferredHeight: Layout.preferredWidth
                    radius: Theme.radiusSmall
                    color: Theme.primaryContainer
                    Image {
                        id: artworkImage
                        anchors.fill: parent
                        source: MediaService.artwork
                        asynchronous: true
                        fillMode: Image.PreserveAspectCrop
                        visible: status === Image.Ready
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: artworkImage.status !== Image.Ready
                        text: "󰎈"
                        color: Theme.primaryContainerText
                        font.family: Config.appearance.monoFontFamily
                        // Theme.iconSmall already carries DisplayScale.primary
                        // and so does hoverIconScale now -- divide back out.
                        font.pixelSize: Math.round(Theme.iconSmall
                            * (Config.island.hoverIconScale / DisplayScale.primary))
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        text: MediaService.title
                        color: AdaptiveColor.glassText
                        font.family: Config.appearance.fontFamily
                        // Theme.textSmall already carries DisplayScale.primary
                        // and so does hoverTextScale now -- divide back out.
                        font.pixelSize: Math.round(Theme.textSmall
                            * (Config.island.hoverTextScale / DisplayScale.primary))
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: MediaService.artist
                        color: AdaptiveColor.glassTextDim
                        font.family: Config.appearance.fontFamily
                        font.pixelSize: Math.round(10
                            * Config.island.hoverTextScale)
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    Component {
        id: audioComponent
        CompactStatus {
            textScale: Config.island.hoverTextScale
            iconScale: Config.island.hoverIconScale
            icon: AudioService.muted ? "󰝟" : "󰕾"
            value: AudioService.available
                ? (AudioService.muted ? "OFF" : AudioService.volumePercent + "%") : "—"
            accent: AudioService.muted ? Theme.error : AdaptiveColor.activeFill
        }
    }
    // Glass redesign: Wi-Fi + Bluetooth are one StatusOrb (ring = Bluetooth
    // signal, arcs = Wi-Fi strength, dots = connected devices) instead of
    // two separate glyphs.
    Component {
        id: networkComponent
        Item {
            implicitWidth: orb.width + Math.round(16 * DisplayScale.primary)
            implicitHeight: orb.height
            StatusOrb {
                id: orb
                anchors.centerIn: parent
                width: Math.round(24 * Config.island.hoverIconScale * DisplayScale.primary)
                height: width
                wifiStrength: ConnectivityStatus.wifiStrength
                ethernet: ConnectivityStatus.ethernet
                btEnabled: ConnectivityStatus.btEnabled
                btSignal: ConnectivityStatus.btSignal
                btDevices: ConnectivityStatus.btDevices
                batteryLevel: BatteryService.available ? BatteryService.percentage : -1
                charging: BatteryService.charging
            }
        }
    }
    Component {
        id: dndComponent
        Item {
            Text {
                visible: NotificationService.count === 0
                anchors.centerIn: parent
                text: NotificationService.doNotDisturb ? "󰂛" : "󰂚"
                color: NotificationService.doNotDisturb ? Theme.tertiary : AdaptiveColor.glassText
                font.family: Config.appearance.monoFontFamily
                font.pixelSize: Math.round(14 * Config.island.hoverIconScale)
            }
            Rectangle {
                visible: NotificationService.count > 0
                anchors.centerIn: parent
                // DisplayScale.primary: bare literals (dot size, badge text)
                // alongside the Config.island.hoverIconScale-derived icon
                // above.
                width: Math.round(15 * DisplayScale.primary); height: width; radius: width / 2
                color: Theme.error
                Text { anchors.fill: parent; anchors.leftMargin: 1; text: NotificationService.count > 99 ? "99+" : NotificationService.count; color: Theme.foregroundFor(parent.color); horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; font.family: Config.appearance.monoFontFamily; font.pixelSize: Math.round(8 * DisplayScale.primary); font.weight: Font.Bold }
            }
        }
    }
    Component {
        id: bluetoothComponent
        // Folded into the Network item's StatusOrb when that item is shown;
        // only stands alone if the owner removed Network from the strip.
        Item {
            readonly property bool merged: Config.island.hoverItemOrder.indexOf("Network") >= 0
            implicitWidth: merged ? 0 : btOrb.width + Math.round(16 * DisplayScale.primary)
            implicitHeight: btOrb.height
            StatusOrb {
                id: btOrb
                anchors.centerIn: parent
                visible: !parent.merged
                width: Math.round(24 * Config.island.hoverIconScale * DisplayScale.primary)
                height: width
                wifiStrength: -1
                btEnabled: ConnectivityStatus.btEnabled
                btSignal: ConnectivityStatus.btSignal
                btDevices: ConnectivityStatus.btDevices
            }
        }
    }

    Component {
        id: keepAwakeComponent
        CompactStatus {
            textScale: Config.island.hoverTextScale
            iconScale: Config.island.hoverIconScale
            iconVerticalOffset: 1
            icon: "󰅶"
            value: ""
            showValue: false
            accent: IdleService.inhibited ? Theme.error : AdaptiveColor.glassText
        }
    }
    Component {
        id: batteryComponent
        // Folded into the Network item's StatusOrb when that item is shown;
        // only stands alone if the owner removed Network from the strip.
        Item {
            readonly property bool merged: Config.island.hoverItemOrder.indexOf("Network") >= 0
            implicitWidth: merged ? 0 : compactBattery.implicitWidth
            implicitHeight: compactBattery.implicitHeight
            CompactStatus {
                id: compactBattery
                anchors.centerIn: parent
                visible: !parent.merged
                textScale: Config.island.hoverTextScale
                iconScale: Config.island.hoverIconScale
                icon: BatteryService.icon
                value: BatteryService.percentageInt + "%"
                accent: BatteryService.percentageInt <= 15 && BatteryService.onBattery
                    ? Theme.error : AdaptiveColor.activeFill
            }
        }
    }

    // Left click: the clock opens the DASHBOARD (the owner's own split --
    // the pill's middle is the way into the control centre), every other
    // status item opens its own card as before. Right click on the clock
    // opens the calendar card instead.
    TapHandler {
        enabled: root.opensControlCenter
        acceptedButtons: Qt.LeftButton
        onTapped: root.controlCenterRequested(
            root.itemId === "Clock" ? "" : root.card)
    }
    TapHandler {
        enabled: root.itemId === "Clock"
        acceptedButtons: Qt.RightButton
        onTapped: root.controlCenterRequested(root.card)
    }
}
