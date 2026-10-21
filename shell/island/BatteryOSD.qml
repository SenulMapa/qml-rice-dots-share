import QtQuick
import QtQuick.Layouts
import "../components"
import "../core"
import "../services"

Item {
    id: root

    // Battery state
    readonly property int batteryPercentage: BatteryService.percentageInt
    readonly property bool isPluggedIn: !BatteryService.onBattery
    readonly property bool isCharging: BatteryService.charging
    readonly property string timeRemaining: BatteryService.timeLabel

    // Sizing
    readonly property bool useVertical: false
    // DisplayScale.primary: bare literals, found during the Task 4 follow-up
    // audit (core/Config.qml's island geometry was the main miss, but this
    // component's own osdWidth/osdHeight -- used at line 89's `width:
    // root.osdWidth - Theme.u(0.4)` -- is the same bug, just local instead
    // of routed through Config).
    readonly property int osdWidth: Math.round(
        (useVertical ? 60 : Math.min(260, 400)) * DisplayScale.primary)
    readonly property int osdHeight: Math.round(
        (useVertical ? Math.min(260, 300) : 60) * DisplayScale.primary)

    // Driven by island/IslandController.qml's `battery` transient. The
    // controller owns how long it stays up, so a call or notification can
    // take the island over, and this OSD never runs a timer of its own.
    property bool shown: false
    onShownChanged: {
        if (shown) {
            hideAnimation.stop()
            showAnimation.restart()
        } else {
            showAnimation.stop()
            hideAnimation.restart()
        }
    }

    // Animation properties
    property real slideY: 80
    property real fadeOpacity: 0

    // Smooth animated percentage
    property real animatedPercentage: 0.0

    Component.onCompleted: {
        animatedPercentage = Math.max(0, Math.min(100, batteryPercentage)) / 100.0;
    }

    onBatteryPercentageChanged: {
        animatedPercentage = Math.max(0, Math.min(100, batteryPercentage)) / 100.0;
    }

    Behavior on animatedPercentage {
        NumberAnimation { duration: 600; easing.type: Easing.OutCubic }
    }

    // Dynamic Material 3 Status Color
    readonly property color statusColor: {
        if (isPluggedIn || isCharging) return "#2ecc71"
        if (batteryPercentage <= 15) return Theme.error
        if (batteryPercentage <= 35) return "#ffa502"
        return AdaptiveColor.activeFill
    }

    // Dynamic Battery Icon
    readonly property string batteryIcon: {
        if (isPluggedIn || isCharging) return "󰂄"
        if (batteryPercentage <= 15) return "󰂃"
        if (batteryPercentage <= 30) return "󰁼"
        if (batteryPercentage >= 95) return "󰁹"
        return "󰁾"
    }

    // Wave animation speeds
    property int chargingWaveSpeed: 1800
    property int dischargingWaveSpeed: 6000

    // Continuous wave movement
    property real phase: 0

    NumberAnimation {
        id: waveAnim
        target: root
        property: "phase"
        from: 0
        to: Math.PI * 2
        duration: root.chargingWaveSpeed
        loops: Animation.Infinite
        running: (isPluggedIn || isCharging) && root.fadeOpacity > 0
    }

    NumberAnimation {
        id: gentleAnim
        target: root
        property: "phase"
        from: 0
        to: Math.PI * 2
        duration: root.dischargingWaveSpeed
        loops: Animation.Infinite
        running: !(isPluggedIn || isCharging) && root.fadeOpacity > 0
    }

    // Main horizontal content
    Item {
        anchors.centerIn: parent
        width: root.osdWidth - Theme.u(0.4)
        y: parent.height / 2 - height / 2 + root.slideY
        opacity: root.fadeOpacity
        // DisplayScale.primary (core/DisplayScale.qml): a bare literal,
        // unlike the Theme.u()-derived sizes around it, so it did not scale
        // on this laptop's higher-PPI panel.
        height: Math.round(40 * DisplayScale.primary)

        // Card container with wave
        Rectangle {
            id: trackBg
            anchors.fill: parent
            radius: Theme.u(0.15)
            color: Theme.surfaceContainer
            border.color: Qt.rgba(root.statusColor.r, root.statusColor.g, root.statusColor.b, 0.3)
            border.width: 1
            clip: true

            // Wave canvas
            Canvas {
                id: waveCanvas
                anchors.fill: parent
                antialiasing: true

                onPaint: {
                    let ctx = getContext("2d")
                    ctx.reset()
                    ctx.clearRect(0, 0, width, height)

                    let radius = Theme.u(0.15)

                    // Clip path for rounded rectangle
                    ctx.beginPath()
                    ctx.moveTo(radius, 0)
                    ctx.lineTo(width - radius, 0)
                    ctx.quadraticCurveTo(width, 0, width, radius)
                    ctx.lineTo(width, height - radius)
                    ctx.quadraticCurveTo(width, height, width - radius, height)
                    ctx.lineTo(radius, height)
                    ctx.quadraticCurveTo(0, height, 0, height - radius)
                    ctx.lineTo(0, radius)
                    ctx.quadraticCurveTo(0, 0, radius, 0)
                    ctx.closePath()
                    ctx.clip()

                    let targetY = height * (1.0 - Math.max(0.02, Math.min(1.0, root.animatedPercentage)))
                    let amp = 2.5
                    let freq = 0.035

                    // Back wave layer (30% opacity)
                    drawWave(ctx, targetY, root.phase + Math.PI, root.statusColor, 0.30, amp, freq)

                    // Front wave layer (70% opacity)
                    drawWave(ctx, targetY, root.phase, root.statusColor, 0.70, amp, freq)

                    // Wave crest stroke
                    ctx.strokeStyle = "#ffffff"
                    ctx.lineWidth = 1.0
                    ctx.globalAlpha = 0.4
                    ctx.beginPath()
                    ctx.moveTo(-10, targetY + amp * Math.sin(root.phase))
                    for (let x = -10; x <= width + 10; x += 4) {
                        let y = targetY + amp * Math.sin(x * freq + root.phase)
                        y = Math.max(-5, Math.min(height + 5, y))
                        ctx.lineTo(x, y)
                    }
                    ctx.stroke()
                }

                function drawWave(ctx, targetY, phaseShift, color, opacity, amp, freq) {
                    ctx.fillStyle = color
                    ctx.globalAlpha = opacity
                    ctx.beginPath()
                    ctx.moveTo(-10, height + 10)
                    ctx.lineTo(-10, targetY)

                    for (let x = -10; x <= width + 10; x += 4) {
                        let y = targetY + amp * Math.sin(x * freq + phaseShift)
                        y = Math.max(-5, Math.min(height + 5, y))
                        ctx.lineTo(x, y)
                    }

                    ctx.lineTo(width + 10, height + 10)
                    ctx.closePath()
                    ctx.fill()
                }

                Connections {
                    target: root
                    function onPhaseChanged() { waveCanvas.requestPaint() }
                    function onAnimatedPercentageChanged() { waveCanvas.requestPaint() }
                    function onStatusColorChanged() { waveCanvas.requestPaint() }
                }
            }

            // Foreground content
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.u(0.2)
                anchors.rightMargin: Theme.u(0.3)
                spacing: Theme.u(0.2)
                z: 10

                // Battery icon badge
                Rectangle {
                    // DisplayScale.primary: bare literals, unlike the
                    // Theme.u()-derived sizes elsewhere in this file.
                    width: Math.round(28 * DisplayScale.primary)
                    height: Math.round(28 * DisplayScale.primary)
                    radius: width / 2
                    color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.4)
                    border.color: Qt.rgba(1, 1, 1, 0.3)
                    border.width: 1
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                        anchors.centerIn: parent
                        text: root.batteryIcon
                        color: "#ffffff"
                        font.family: Config.appearance.monoFontFamily
                        font.pixelSize: Math.round(16 * DisplayScale.primary)
                    }
                }

                // Text content
                Column {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: -1

                    Row {
                        spacing: Theme.u(0.15)

                        Text {
                            text: root.batteryPercentage + "%"
                            color: "#ffffff"
                            font.family: Config.appearance.monoFontFamily
                            font.pixelSize: Theme.textBody
                            font.weight: Font.Bold
                        }

                        Text {
                            text: (isPluggedIn || isCharging) ? "Charging" : (batteryPercentage <= 20 ? "Low Battery" : "Discharging")
                            color: Qt.rgba(1, 1, 1, 0.95)
                            font.family: Config.appearance.fontFamily
                            font.pixelSize: Theme.textSmall
                            font.weight: Font.Medium
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Text {
                        text: root.timeRemaining ? root.timeRemaining : ((isPluggedIn || isCharging) ? "Connected to AC" : "On Battery")
                        color: Qt.rgba(1, 1, 1, 0.8)
                        font.family: Config.appearance.fontFamily
                        font.pixelSize: Math.round(10 * DisplayScale.primary)
                    }
                }
            }
        }
    }

    // Show animation (slide up from bottom)
    NumberAnimation {
        id: showAnimation
        target: root
        property: "slideY"
        from: 80
        to: 0
        duration: 300
        easing.type: Easing.OutCubic
        onStarted: {
            root.fadeOpacity = 1
            root.visible = true
        }
    }

    // Hide animation (slide down and fade out)
    SequentialAnimation {
        id: hideAnimation
        NumberAnimation {
            target: root
            property: "slideY"
            from: 0
            to: 80
            duration: 250
            easing.type: Easing.InCubic
        }
        NumberAnimation {
            target: root
            property: "fadeOpacity"
            from: 1
            to: 0
            duration: 200
        }
        onFinished: {
            root.visible = false
            root.slideY = 80
            root.fadeOpacity = 0
        }
    }
}
