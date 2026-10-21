import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"

/**
 * PhoneSatelliteContent -- the right-hand "phone" satellite: device name,
 * battery (+ charging glyph), signal bars and network, then the hotspot /
 * lock-on-leave switches, the AirPlay / camera rows and an "Open Messages"
 * row. `service` is overridable so render-phone.qml and the tests can drive
 * it with a stub.
 *
 * Every row derives from one value: `networkTrusted` (status.trustedNetwork).
 * AirPlay and the camera only run on a trusted network (netgate.py), so while
 * untrusted their rows are replaced by one "AirPlay & camera" line and the
 * trust toggle offers the action that applies ("Trust this network" or
 * "Stop trusting this network", never both).
 */
Item {
    id: root

    property var service: PhoneService
    property bool lockOnLeaveValue: Config.phone.lockOnLeave
    signal openMessagesRequested()

    // One row height and one gap for every row, matching ConnectivityRow and
    // the audio device rows (ink: 44, Theme.u(0.2) spacing in ControlDetailPanel).
    readonly property int rowHeight: 44
    readonly property real rowGap: Theme.u(0.2)

    readonly property var status: service ? service.status : null
    readonly property bool connected: service ? service.connected === true : false
    readonly property string deviceName: status && status.device && status.device.name
        ? status.device.name : "iPhone"
    readonly property var battery: connected && status ? status.battery : null
    readonly property bool charging: connected && status && status.charging === true
    // Signal is null when calls are off (no ofono): hide the bars, do not draw empty ones.
    readonly property bool signalKnown: connected && status && typeof status.signal === "number"
    readonly property int signalBars: signalKnown ? Math.max(0, Math.min(4, status.signal)) : 0
    readonly property string network: connected && status && status.network ? status.network : ""
    readonly property bool hotspotActive: status && status.hotspot ? status.hotspot.active === true : false
    readonly property bool hotspotAvailable: connected && status && status.hotspot
        ? status.hotspot.available === true : false
    readonly property string errorText: !connected && status && status.error ? status.error : ""

    // The single source for every network-dependent row.
    readonly property bool networkTrusted: status ? status.trustedNetwork === true : false
    // AirPlay and the camera exist only while the network is trusted.
    readonly property bool mediaAvailable: networkTrusted

    readonly property string airplayState: service && service.airplayState ? service.airplayState : "idle"
    readonly property string airplayValue: !mediaAvailable ? "Off"
        : airplayState === "pin" ? "Needs password"
        : airplayState === "mirroring" ? "Mirroring"
        : airplayState === "audio" ? "Audio" : "Ready"
    function toggleNetworkTrust(): void {
        if (!service)
            return
        if (networkTrusted)
            service.untrustNetwork?.()
        else
            service.trustNetwork?.()
    }
    readonly property bool cameraLive: mediaAvailable && service && service.cameraActive === true
    // Camera setup QR view: the Larix Grove deep link from `phonectl camera-link`.
    property bool qrOpen: false
    property string cameraUrl: ""
    property string cameraError: ""
    function openCameraSetup(): void {
        cameraUrl = ""
        cameraError = ""
        qrOpen = true
        if (!service || !service.cameraLink) {
            cameraError = "Camera link unavailable"
            return
        }
        service.cameraLink(res => {
            if (res && res.ok !== false && res.url)
                root.cameraUrl = String(res.url)
            else
                root.cameraError = res && res.error ? String(res.error) : "Camera link unavailable"
        })
    }

    // AirPlay password: fetched on request, shown inline, never kept longer
    // than revealMs, never while locked, cleared when the satellite closes.
    property string revealedPassword: ""
    property string passwordError: ""
    property int revealMs: 60000
    readonly property bool passwordRevealed: revealedPassword.length > 0
    // Blocks of 4 separated by U+2009, 4 blocks per line. Pure.
    function groupPassword(text: string): string {
        const blocks = []
        for (let i = 0; i < text.length; i += 4)
            blocks.push(text.substr(i, 4))
        const lines = []
        for (let i = 0; i < blocks.length; i += 4)
            lines.push(blocks.slice(i, i + 4).join(" "))
        return lines.join("\n")
    }
    function clearReveal(): void {
        revealedPassword = ""
        passwordError = ""
        revealTimer.stop()
    }
    function toggleAirplayPassword(): void {
        if (passwordRevealed) {
            clearReveal()
            return
        }
        if (PhoneAttention.locked)
            return
        passwordError = ""
        if (!service || !service.airplayPassword) {
            passwordError = "Password unavailable"
            return
        }
        service.airplayPassword(res => {
            if (PhoneAttention.locked)
                return
            if (res && res.ok !== false && res.password) {
                root.revealedPassword = String(res.password)
                revealTimer.interval = root.revealMs
                revealTimer.restart()
            } else {
                root.passwordError = res && res.error ? String(res.error) : "Password unavailable"
            }
        })
    }
    Timer { id: revealTimer; repeat: false; onTriggered: root.clearReveal() }
    onVisibleChanged: if (!visible) clearReveal()
    Component.onDestruction: revealedPassword = ""
    Connections {
        target: PhoneAttention
        function onLockedChanged(): void { if (PhoneAttention.locked) root.clearReveal() }
    }

    // Lock-distance calibration (phonectl calibrate-presence, ~10 s). One run at a time.
    property bool calibrating: false
    property bool calibrateError: false
    property string calibrateText: "Tap to set where it locks"
    function startCalibration(): void {
        if (calibrating || !service || !service.calibratePresence)
            return
        calibrating = true
        calibrateError = false
        calibrateText = "Measuring… stand where it should lock"
        service.calibratePresence(res => {
            calibrating = false
            if (res && res.ok === true && typeof res.threshold === "number") {
                calibrateText = "Locks beyond " + res.threshold + " dBm"
                return
            }
            const msg = res && res.error ? String(res.error) : "Calibration failed"
            calibrateError = true
            calibrateText = msg.indexOf("install tools/phone/rssi") >= 0
                ? "Install the signal helper first" : msg
        })
    }

    readonly property int contentHeight: Math.round(column.implicitHeight + 36)

    ColumnLayout {
        id: column
        visible: !root.qrOpen
        anchors.fill: parent
        anchors.margins: 18
        spacing: root.rowGap

        Text {

            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: root.deviceName
            color: root.connected ? Theme.t1 : Theme.t3
            elide: Text.ElideRight
            font.family: Theme.fontUi
            font.pixelSize: 20
            font.weight: Font.DemiBold
            font.letterSpacing: -0.3
        }

        Text {

            textFormat: Text.PlainText
            Layout.fillWidth: true
            visible: !root.connected
            text: root.errorText.length > 0 ? "Not connected  ·  " + root.errorText : "Not connected"
            color: Theme.t3
            elide: Text.ElideRight
            font.family: Theme.fontUi
            font.pixelSize: 13
            font.weight: Font.Medium
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 8
            Layout.bottomMargin: 8
            visible: root.connected
            spacing: 18

            RowLayout {
                spacing: 6
                Icon {
                    name: root.charging ? "battery-charging" : "battery-full"
                    size: 18
                    color: Theme.t1
                }
                Text {
                    textFormat: Text.PlainText
                    text: root.battery !== null && root.battery !== undefined ? root.battery + "%" : "—"
                    color: Theme.t1
                    font.family: Theme.fontSerif
                    font.pixelSize: 26
                }
            }

            RowLayout {
                spacing: 8
                visible: root.signalKnown || root.network.length > 0
                Row {
                    spacing: 3
                    visible: root.signalKnown
                    Layout.alignment: Qt.AlignVCenter
                    Repeater {
                        model: 4
                        delegate: Rectangle {
                            required property int index
                            anchors.bottom: parent.bottom
                            width: 4
                            height: 5 + index * 4
                            radius: 1.5
                            color: index < root.signalBars ? Theme.t1 : Theme.inkRaised2
                        }
                    }
                }
                Text {
                    textFormat: Text.PlainText
                    visible: root.network.length > 0
                    text: root.network
                    color: Theme.t2
                    font.family: Theme.fontUi
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
            }
            Item { Layout.fillWidth: true }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: root.connected ? 0 : 10
            visible: !root.connected
        }

        // Switch rows
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: root.rowHeight
            opacity: root.hotspotAvailable ? 1 : 0.5
            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: "Use iPhone hotspot"
                color: Theme.t1
                font.family: Theme.fontUi
                font.pixelSize: 14
                font.weight: Font.Medium
            }
            SettingsToggle {
                checked: root.hotspotActive
                available: root.hotspotAvailable
                onToggled: value => root.service?.setHotspot(value)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: root.rowHeight
            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: "Lock when iPhone leaves"
                color: Theme.t1
                font.family: Theme.fontUi
                font.pixelSize: 14
                font.weight: Font.Medium
            }
            SettingsToggle {
                checked: root.lockOnLeaveValue
                onToggled: value => root.service?.setLockOnLeave(value)
            }
        }

        // Lock distance: only while lock-on-leave is on. Label on the first line, the state of
        // the last measurement on the second, both inside the 44px row.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: root.rowHeight
            visible: root.lockOnLeaveValue
            scale: calTap.pressed ? 0.98 : 1
            Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
            // Measuring: the whole row is the status, wrapped to two lines (it is 10 s long).
            Text {
                textFormat: Text.PlainText
                anchors.fill: parent
                visible: root.calibrating
                wrapMode: Text.WordWrap
                verticalAlignment: Text.AlignVCenter
                text: root.calibrateText
                color: Theme.t2
                font.family: Theme.fontUi
                font.pixelSize: 13
                font.weight: Font.Medium
            }
            ColumnLayout {
                anchors.fill: parent
                spacing: 0
                visible: !root.calibrating
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: "Calibrate distance"
                    color: Theme.t1
                    elide: Text.ElideRight
                    font.family: Theme.fontUi
                    font.pixelSize: 14
                    font.weight: Font.Medium
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: root.calibrateText
                    color: root.calibrateError ? "#ff453a" : Theme.t3
                    elide: Text.ElideRight
                    font.family: Theme.fontUi
                    font.pixelSize: 12
                    font.weight: Font.Medium
                }
            }
            TapHandler { id: calTap; onTapped: root.startCalibration() }
        }

        // Untrusted network: one honest line instead of AirPlay / camera rows.
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: root.rowHeight
            visible: !root.mediaAvailable
            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: "AirPlay & camera"
                color: Theme.t1
                font.family: Theme.fontUi
                font.pixelSize: 14
                font.weight: Font.Medium
            }
            Text {
                textFormat: Text.PlainText
                text: "Off on this network"
                color: Theme.t3
                font.family: Theme.fontUi
                font.pixelSize: 13
                font.weight: Font.Medium
            }
        }

        // Trusted network: AirPlay, password, camera and camera setup.
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: root.rowHeight
            visible: root.mediaAvailable
            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: "AirPlay"
                color: Theme.t1
                font.family: Theme.fontUi
                font.pixelSize: 14
                font.weight: Font.Medium
            }
            Text {
                textFormat: Text.PlainText
                text: root.airplayValue
                color: root.airplayState === "idle" ? Theme.t3 : Theme.t1
                font.family: Theme.fontUi
                font.pixelSize: 13
                font.weight: Font.Medium
            }
        }

        Item {
            Layout.fillWidth: true
            // Grows only while a password or its error is on screen.
            Layout.preferredHeight: root.passwordRevealed || root.passwordError.length > 0
                ? root.rowHeight + 40 : root.rowHeight
            visible: root.mediaAvailable
            scale: pwTap.pressed ? 0.98 : 1
            Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
            ColumnLayout {
                anchors.fill: parent
                spacing: root.rowGap / 2
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.rowHeight
                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: "AirPlay password"
                        color: Theme.t1
                        font.family: Theme.fontUi
                        font.pixelSize: 14
                        font.weight: Font.Medium
                    }
                    Text {
                        textFormat: Text.PlainText
                        text: root.passwordRevealed ? "Hide" : "Show"
                        color: Theme.t2
                        font.family: Theme.fontUi
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    visible: root.passwordRevealed
                    text: root.groupPassword(root.revealedPassword)
                    color: Theme.t1
                    font.family: Theme.fontData
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    lineHeight: 1.15
                }
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    visible: root.passwordError.length > 0
                    text: root.passwordError
                    color: "#ff453a"
                    elide: Text.ElideRight
                    font.family: Theme.fontUi
                    font.pixelSize: 12
                }
            }
            TapHandler { id: pwTap; onTapped: root.toggleAirplayPassword() }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: root.rowHeight
            visible: root.mediaAvailable
            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: "Camera"
                color: Theme.t1
                font.family: Theme.fontUi
                font.pixelSize: 14
                font.weight: Font.Medium
            }
            Rectangle {
                visible: root.cameraLive
                Layout.preferredWidth: 7
                Layout.preferredHeight: 7
                radius: 3.5
                color: "#32d74b"
            }
            Text {
                textFormat: Text.PlainText
                text: root.cameraLive ? "Live" : "Off"
                color: root.cameraLive ? Theme.t1 : Theme.t3
                font.family: Theme.fontUi
                font.pixelSize: 13
                font.weight: Font.Medium
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: root.rowHeight
            visible: root.mediaAvailable
            scale: camTap.pressed ? 0.98 : 1
            Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
            RowLayout {
                anchors.fill: parent
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: "Camera setup"
                    color: Theme.t1
                    font.family: Theme.fontUi
                    font.pixelSize: 14
                    font.weight: Font.Medium
                }
                Icon {
                    name: "arrow-right"
                    size: 16
                    color: Theme.t2
                }
            }
            TapHandler { id: camTap; onTapped: root.openCameraSetup() }
        }

        // One trust action, whichever state the network is in.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: root.rowHeight
            scale: trustTap.pressed ? 0.98 : 1
            Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
            RowLayout {
                anchors.fill: parent
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: root.networkTrusted ? "Stop trusting this network" : "Trust this network"
                    color: Theme.t1
                    font.family: Theme.fontUi
                    font.pixelSize: 14
                    font.weight: Font.Medium
                }
            }
            TapHandler { id: trustTap; onTapped: root.toggleNetworkTrust() }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: root.rowHeight
            scale: openTap.pressed ? 0.98 : 1
            Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
            RowLayout {
                anchors.fill: parent
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: "Open Messages"
                    color: Theme.t1
                    font.family: Theme.fontUi
                    font.pixelSize: 14
                    font.weight: Font.Medium
                }
                Icon {
                    name: "arrow-right"
                    size: 16
                    color: Theme.t2
                }
            }
            TapHandler { id: openTap; onTapped: root.openMessagesRequested() }
        }
    }

    // Camera setup QR view, over the whole satellite.
    Rectangle {
        id: qrView
        anchors.fill: parent
        visible: root.qrOpen
        // Transparent: the island body paints the ink; the rows are hidden.
        color: "transparent"

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 12

            QrCode {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 176
                Layout.preferredHeight: 176
                visible: root.cameraUrl.length > 0
                text: root.cameraUrl
            }
            Text {
                textFormat: Text.PlainText
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: root.width - 36
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: root.cameraError.length > 0 ? root.cameraError
                    : root.cameraUrl.length > 0 ? "Scan with Larix Broadcaster on your iPhone"
                    : "Preparing…"
                color: root.cameraError.length > 0 ? "#ff453a" : Theme.t2
                font.family: Theme.fontUi
                font.pixelSize: 13
                font.weight: Font.Medium
            }
            Text {
                textFormat: Text.PlainText
                Layout.alignment: Qt.AlignHCenter
                text: "Done"
                color: Theme.t1
                font.family: Theme.fontUi
                font.pixelSize: 14
                font.weight: Font.DemiBold
                TapHandler { onTapped: root.qrOpen = false }
            }
        }
    }
}
