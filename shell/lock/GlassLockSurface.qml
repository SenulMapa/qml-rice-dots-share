pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtMultimedia
import "../core"
import "../components"
import "../services" as Services

/**
 * GlassLockSurface -- the "liquid glass" login/lock screen (Figma "Login
 * screen", password frame, plus the user-list frame's big clock on top).
 * Single user, so the Figma user picker, "Back to users" and "Forgot
 * Password?" are intentionally absent.
 *
 * Takes the same `context` shape as AsciiLockSurface (LockContext,
 * GreetdContext or their fakes): state/locked/authenticating/failed/
 * unlocking, submit(), acknowledgeFailure(), finishUnlockAnimation(),
 * wrongPassword(). So it can stand in for AsciiLockSurface in both the
 * lock screen and the greetd greeter.
 *
 * Every glass element refracts `wallpaper`, which plays the video itself:
 * a separate wallpaper process (gSlapper) is invisible to this scene graph,
 * so the glass would have nothing to bend.
 *
 * Geometry is the Figma 1920x1080 frame scaled uniformly by `s`.
 */
Item {
    id: root
    focus: true

    required property QtObject context

    property url videoSource
    // Shown when there is no video (a still wallpaper) or until it starts.
    property url stillSource
    property url avatarSource
    property string userName: ""
    property string footer: "Arch Linux"
    // False in previews/renders: nothing takes keyboard focus.
    property bool interactive: true
    // Anything with wifiStrength/ethernet/btEnabled/btSignal/btDevices.
    property QtObject connectivity: Services.ConnectivityStatus

    // 3D tilting clock (lock screen) vs a still slab (greeter).
    property bool clock3d: true
    property bool reducedMotion: false
    // Harnesses can pin the clock's pointer (in clock coordinates).
    property var clockPointer: null

    // Lets harnesses drive the field without synthetic key events.
    property alias passwordText: field.text

    signal suspendRequested()
    signal rebootRequested()
    signal poweroffRequested()

    readonly property real s: Math.min(width / 1920, height / 1080)
    readonly property bool busy: context.state === context.authenticating
                                 || context.state === context.unlocking

    // The glass avatar ring gradient, used only when ink is off.
    Gradient {
        id: glassAvatarGradient
        GradientStop { position: 0; color: "#ff4d6d" }
        GradientStop { position: 1; color: "#b5179e" }
    }

    FontLoader { id: poppins; source: Qt.resolvedUrl("../assets/fonts/Poppins-SemiBold.ttf") }
    FontLoader { id: poppinsMedium; source: Qt.resolvedUrl("../assets/fonts/Poppins-Medium.ttf") }
    FontLoader { id: poppinsRegular; source: Qt.resolvedUrl("../assets/fonts/Poppins-Regular.ttf") }

    // ---- Wallpaper: the only thing the glass refracts ----
    Item {
        id: wallpaper
        anchors.fill: parent

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: "#2a0f3d" }
                GradientStop { position: 0.55; color: "#1a0a2a" }
                GradientStop { position: 1; color: "#0c0614" }
            }
        }

        Image {
            anchors.fill: parent
            source: root.stillSource
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: root.stillSource.toString() !== "" && !video.visible
        }

        // Every frame of a playing video re-runs all the LiquidGlass blur
        // passes below, so it plays only while this surface is shown and not
        // on battery; otherwise it holds a frame (the glass still refracts it).
        Video {
            id: video
            anchors.fill: parent
            visible: root.videoSource.toString() !== "" && video.hasVideo
            source: root.videoSource
            muted: true
            loops: MediaPlayer.Infinite
            autoPlay: false
            fillMode: VideoOutput.PreserveAspectCrop
            readonly property bool shouldPlay: root.visible
                && !Services.BatteryService.onBattery
            function sync(): void {
                if (root.videoSource.toString() === "")
                    return
                if (shouldPlay)
                    play()
                else
                    pause()
            }
            onShouldPlayChanged: sync()
            onSourceChanged: sync()
            Component.onCompleted: sync()
        }

        // Darken the top and bottom bands where the white text sits.
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.28) }
                GradientStop { position: 0.4; color: Qt.rgba(0, 0, 0, 0.0) }
                GradientStop { position: 0.75; color: Qt.rgba(0, 0, 0, 0.05) }
                GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.35) }
            }
        }
    }

    HoverHandler { id: pointerTracker }

    // ---- Everything above the wallpaper fades together on unlock ----
    Item {
        id: ui
        anchors.fill: parent

        // Clock
        property date now: new Date()
        Timer {
            interval: 1000; running: root.visible; repeat: true
            triggeredOnStart: true
            onTriggered: ui.now = new Date()
        }

        // Lock screen: the 3D "glass slabs" clock that tilts toward the
        // pointer and drifts when idle. The greeter passes clock3d: false
        // (no pointer before login) and gets the same slab, held still.
        GlassClock3D {
            id: clock
            visible: !Config.appearance.ink
            backgroundItem: wallpaper
            now: ui.now
            fontFamily: poppins.name
            pixelSize: 210 * root.s
            depth: 14 * root.s
            tilt: root.clock3d
            reducedMotion: root.reducedMotion
            pointer: root.clockPointer !== null ? root.clockPointer
                : (pointerTracker.hovered
                   ? Qt.point(pointerTracker.point.position.x - x,
                              pointerTracker.point.position.y - y) : null)
            x: (root.width - width) / 2
            y: 130 * root.s
        }

        // Ink lock (lock.html): Instrument Serif clock in the upper third and
        // a Geist date under it. Replaces the glass clock when ink is on.
        Text {
            id: inkClock
            visible: Config.appearance.ink
            anchors.horizontalCenter: parent.horizontalCenter
            y: 170 * root.s
            text: Qt.formatTime(ui.now, "HH:mm")
            font.family: Theme.fontSerif
            font.pixelSize: 160 * root.s
            color: Theme.t1
        }
        Text {
            id: inkDate
            visible: Config.appearance.ink
            anchors.horizontalCenter: parent.horizontalCenter
            y: 344 * root.s
            text: Qt.formatDate(ui.now, "dddd, d MMMM")
            font.family: Theme.fontUi
            font.pixelSize: 20 * root.s
            font.weight: Font.Medium
            color: Theme.t1
        }

        // Avatar with the Figma's thick white ring (glass) or a 72px disc (ink)
        Item {
            id: avatar
            width: (Config.appearance.ink ? 72 : 185) * root.s; height: width
            x: (root.width - width) / 2
            y: (Config.appearance.ink ? 708 : 430) * root.s

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "white"
                visible: !Config.appearance.ink
            }
            Rectangle {
                id: avatarFallback
                anchors.fill: parent
                anchors.margins: (Config.appearance.ink ? 0 : 14) * root.s
                radius: width / 2
                visible: avatarImage.status !== Image.Ready
                color: Config.appearance.ink ? Theme.inkRaised : "transparent"
                gradient: Config.appearance.ink ? null : glassAvatarGradient
                Text {
                    anchors.centerIn: parent
                    text: (root.userName || "?").charAt(0).toUpperCase()
                    font.family: Config.appearance.ink ? Theme.fontUi : poppins.name
                    font.weight: Config.appearance.ink ? Font.DemiBold : Font.Normal
                    font.pixelSize: (Config.appearance.ink ? 28 : 72) * root.s
                    color: Config.appearance.ink ? Theme.t1 : "white"
                }
            }
            Image {
                id: avatarImage
                anchors.fill: parent
                anchors.margins: (Config.appearance.ink ? 0 : 14) * root.s
                source: root.avatarSource
                fillMode: Image.PreserveAspectCrop
                visible: false
                sourceSize: Qt.size(width * 2, height * 2)
            }
            Rectangle {
                id: avatarMask
                anchors.fill: avatarImage
                radius: width / 2
                visible: false
                layer.enabled: true
            }
            MultiEffect {
                anchors.fill: avatarImage
                visible: avatarImage.status === Image.Ready
                source: avatarImage
                maskEnabled: true
                maskSource: avatarMask
            }
        }

        Text {
            id: nameText
            anchors.horizontalCenter: parent.horizontalCenter
            y: 628 * root.s
            text: root.userName
            visible: !Config.appearance.ink
            font.family: poppins.name
            font.weight: Font.DemiBold
            font.pixelSize: 46 * root.s
            color: "white"
        }

        // Eye / password / submit row. Empty, the pill is just wide enough for
        // its placeholder and the two buttons hug it; typing grows it out from
        // the centre to fit the dots, up to the Figma's 472px, and the buttons
        // ride its edges. SmoothedAnimation keeps the current velocity when
        // the target moves mid-flight, so fast typing is one continuous glide
        // instead of a restart per keystroke.
        Item {
            id: row
            // Ink (lock.html): a 340x56 capsule at y 798 instead of the glass row.
            width: (Config.appearance.ink ? 340 : 640) * root.s
            height: (Config.appearance.ink ? 56 : 64) * root.s
            x: (root.width - width) / 2
            y: (Config.appearance.ink ? 798 : 726) * root.s
            opacity: root.busy ? 0.6 : 1
            Behavior on opacity { NumberAnimation { duration: 180 } }
            transform: Translate { id: shake }

            readonly property real pad: (Config.appearance.ink ? 22 : 32) * root.s
            // Empty, the field is a circle the size of the buttons beside it.
            readonly property real minPill: height
            readonly property real maxPill: (Config.appearance.ink ? 340 : 472) * root.s
            readonly property real dotStep: 17 * root.s
            readonly property int maxDots: Math.floor((maxPill - 2 * pad) / dotStep)
            readonly property bool reveal: field.echoMode === TextInput.Normal
            readonly property real contentW: reveal
                ? plain.implicitWidth
                : Math.min(field.text.length, maxDots) * dotStep
            // Grow a little ahead of the content so a new dot never lands
            // outside the pill while it is still widening.
            readonly property real targetPill: Config.appearance.ink ? maxPill
                : field.text.length === 0 ? minPill
                : Math.max(minPill, Math.min(maxPill, contentW + 2 * pad + 20 * root.s))

            // A stable model: an integer Repeater model rebuilds every
            // delegate when it changes, which would re-pop all dots on each
            // keystroke. Appending/removing only touches the dot that changed.
            ListModel { id: dotModel }
            readonly property int dotCount: Math.min(field.text.length, maxDots)
            onDotCountChanged: {
                while (dotModel.count < dotCount) dotModel.append({});
                while (dotModel.count > dotCount) dotModel.remove(dotModel.count - 1);
            }
            property real pillWidth: targetPill
            Behavior on pillWidth {
                SmoothedAnimation { velocity: -1; duration: 260; reversingMode: SmoothedAnimation.Sync }
            }

            GlassCircle {
                id: eye
                visible: !Config.appearance.ink
                x: pill.x - width - 20 * root.s
                icon: field.echoMode === TextInput.Password ? "visibility_off" : "visibility"
                onClicked: field.echoMode = field.echoMode === TextInput.Password
                           ? TextInput.Normal : TextInput.Password
            }

            LiquidGlass {
                id: pill
                visible: !Config.appearance.ink
                backgroundItem: wallpaper
                width: row.pillWidth; height: parent.height
                x: (row.width - width) / 2
                milk: 0.06
                outline: 0.7
                shapeRadius: height / 2
                tint: Qt.rgba(0.06, 0.02, 0.1, 0.25)
                Rectangle { anchors.fill: parent; radius: height / 2; color: "white" }
            }
            // Ink capsule: same geometry as the glass pill, inkRaised fill.
            Rectangle {
                anchors.fill: pill
                visible: Config.appearance.ink
                radius: height / 2
                color: Theme.inkRaised
            }
            // The real input, kept invisible: it owns focus, keys and the
            // text. What you see is drawn below, so the dots can animate and
            // never scroll out of view the way TextInput's own overflow does.
            TextInput {
                id: field
                anchors.fill: pill
                anchors.leftMargin: row.pad
                anchors.rightMargin: row.pad
                opacity: 0
                echoMode: TextInput.Password
                font.family: poppinsRegular.name
                font.pixelSize: 20 * root.s
                enabled: !root.busy
                focus: root.interactive
                onAccepted: row.submit()
                Keys.onEscapePressed: field.text = ""
            }

            // Hidden: one dot per character (newest kept when it overflows),
            // each popping in.
            Row {
                anchors.centerIn: pill
                visible: !row.reveal
                Repeater {
                    model: dotModel
                    delegate: Item {
                        width: row.dotStep; height: row.dotStep
                        Rectangle {
                            id: dot
                            anchors.centerIn: parent
                            width: 9 * root.s; height: width; radius: width / 2
                            color: Config.appearance.ink ? Theme.t1 : "white"
                            scale: 0.2; opacity: 0
                            Component.onCompleted: popIn.start()
                            ParallelAnimation {
                                id: popIn
                                NumberAnimation { target: dot; property: "scale"; to: 1; duration: 170; easing.type: Easing.OutCubic }
                                NumberAnimation { target: dot; property: "opacity"; to: 1; duration: 120 }
                            }
                        }
                    }
                }
            }

            // Revealed (eye toggled): the plain text, newest end kept visible.
            Text {
                id: plain
                anchors.centerIn: pill
                width: Math.min(implicitWidth, pill.width - 2 * row.pad)
                visible: row.reveal
                text: field.text
                elide: Text.ElideLeft
                font: field.font
                color: Config.appearance.ink ? Theme.t1 : "white"
            }

            // Empty-state glyph inside the circle; fades as the first dot pops.
            // Ink placeholder: the word, left-aligned in the capsule.
            Text {
                visible: Config.appearance.ink
                anchors.left: pill.left
                anchors.leftMargin: row.pad
                anchors.verticalCenter: pill.verticalCenter
                opacity: field.text.length === 0 ? 1 : 0
                text: "Password"
                font.family: Theme.fontUi
                font.pixelSize: 15 * root.s
                color: Theme.t2
            }

            Text {
                id: placeholder
                visible: !Config.appearance.ink
                anchors.centerIn: pill
                opacity: field.text.length === 0 ? 0.8 : 0
                scale: field.text.length === 0 ? 1 : 0.6
                Behavior on opacity { NumberAnimation { duration: 110 } }
                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                text: "password"
                font.family: "Material Symbols Rounded"
                font.pixelSize: 24 * root.s
                color: "white"
            }

            // Ink submit (lock.html): a 44px fillOn disc inside the capsule.
            Rectangle {
                id: inkGo
                visible: Config.appearance.ink
                width: 44 * root.s; height: width; radius: width / 2
                x: pill.x + pill.width - width - 6 * root.s
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.fillOn
                Text {
                    anchors.centerIn: parent
                    text: "arrow_forward"
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: 18 * root.s
                    color: Theme.glyphOn
                }
                TapHandler {
                    enabled: Config.appearance.ink
                    onTapped: row.submit()
                }
            }

            GlassCircle {
                id: go
                visible: !Config.appearance.ink
                x: pill.x + pill.width + 20 * root.s
                icon: "arrow_forward"
                onClicked: row.submit()
            }

            function submit() {
                if (root.busy || field.text.length === 0)
                    return;
                root.context.submit(field.text);
            }

            SequentialAnimation {
                id: shakeAnim
                loops: 1
                NumberAnimation { target: shake; property: "x"; to: -18 * root.s; duration: 60; easing.type: Easing.OutQuad }
                NumberAnimation { target: shake; property: "x"; to: 14 * root.s; duration: 90; easing.type: Easing.InOutQuad }
                NumberAnimation { target: shake; property: "x"; to: -8 * root.s; duration: 80; easing.type: Easing.InOutQuad }
                NumberAnimation { target: shake; property: "x"; to: 0; duration: 90; easing.type: Easing.OutQuad }
                ScriptAction {
                    script: {
                        field.text = "";
                        root.context.acknowledgeFailure();
                    }
                }
            }
        }

        // Ink media capsule (lock.html). Shown only while an MPRIS player is
        // active, so the greeter, which has no session player, never shows it.
        Rectangle {
            id: inkMedia
            visible: Config.appearance.ink && Services.MediaService.available
            width: 420 * root.s; height: 68 * root.s
            radius: height / 2
            x: (root.width - width) / 2
            y: 608 * root.s
            color: Theme.inkRaised

            Rectangle {
                id: inkArt
                x: 12 * root.s
                anchors.verticalCenter: parent.verticalCenter
                width: 44 * root.s; height: width
                radius: 12 * root.s
                color: Theme.inkRaised2
                clip: true
                Image {
                    anchors.fill: parent
                    source: Services.MediaService.artwork
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize: Qt.size(88, 88)
                }
            }

            Column {
                anchors.left: inkArt.right
                anchors.leftMargin: 12 * root.s
                anchors.right: inkPlay.left
                anchors.rightMargin: 12 * root.s
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: Services.MediaService.title
                    font.family: Theme.fontUi
                    font.pixelSize: 14 * root.s
                    font.weight: Font.DemiBold
                    color: Theme.t1
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: Services.MediaService.artist
                    font.family: Theme.fontUi
                    font.pixelSize: 12 * root.s
                    color: Theme.t2
                }
            }

            Rectangle {
                id: inkPlay
                anchors.verticalCenter: parent.verticalCenter
                x: parent.width - width - 16 * root.s
                width: 36 * root.s; height: width
                radius: width / 2
                color: Theme.fillOn
                Text {
                    anchors.centerIn: parent
                    text: Services.MediaService.playing ? "pause" : "play_arrow"
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: 16 * root.s
                    color: Theme.glyphOn
                }
                TapHandler {
                    enabled: Services.MediaService.canToggle
                    onTapped: Services.MediaService.togglePlaying()
                }
            }
        }

        // Power pill + dropdown (top right)
        Item {
            id: power
            width: 71 * root.s; height: 35 * root.s
            x: 1753 * root.s + (root.width - 1920 * root.s)
            y: 40 * root.s
            property bool open: false

            LiquidGlass {
                anchors.fill: parent
                backgroundItem: wallpaper
                milk: 0.04
                rim: 0.5
                edgeRadius: 4
                outline: 0.7
                shapeRadius: height / 2
                tint: Qt.rgba(0.06, 0.02, 0.1, 0.45)
                Rectangle { anchors.fill: parent; radius: height / 2; color: "white" }
            }
            Row {
                anchors.centerIn: parent
                spacing: 2 * root.s
                Text {
                    text: "power_settings_new"
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: 18 * root.s
                    color: "white"
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "arrow_drop_down"
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: 18 * root.s
                    color: "white"
                    rotation: power.open ? 180 : 0
                    Behavior on rotation { NumberAnimation { duration: 160 } }
                }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: power.open = !power.open
            }
        }

        LiquidGlass {
            id: powerMenu
            backgroundItem: wallpaper
            width: 190 * root.s
            height: menuColumn.implicitHeight + 16 * root.s
            x: power.x + power.width - width
            y: power.y + power.height + 10 * root.s
            visible: opacity > 0
            opacity: power.open ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 140 } }
            milk: 0.04
            rim: 0.5
            tint: Qt.rgba(0.06, 0.02, 0.1, 0.55)
            Rectangle { anchors.fill: parent; radius: 18 * root.s; color: "white" }
        }
        Column {
            id: menuColumn
            x: powerMenu.x; y: powerMenu.y + 8 * root.s
            width: powerMenu.width
            visible: powerMenu.visible
            opacity: powerMenu.opacity
            Repeater {
                model: [
                    { icon: "bedtime", label: "Sleep", act: () => root.suspendRequested() },
                    { icon: "restart_alt", label: "Restart", act: () => root.rebootRequested() },
                    { icon: "power_settings_new", label: "Shut down", act: () => root.poweroffRequested() }
                ]
                delegate: Item {
                    required property var modelData
                    width: menuColumn.width; height: 44 * root.s
                    Squircle {
                        anchors.fill: parent
                        anchors.leftMargin: 8 * root.s; anchors.rightMargin: 8 * root.s
                        radius: 12 * root.s
                        color: hover.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                    }
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        x: 20 * root.s
                        spacing: 12 * root.s
                        Text {
                            text: modelData.icon
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: 20 * root.s
                            color: "white"
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label
                            font.family: poppinsMedium.name
                            font.pixelSize: 16 * root.s
                            color: "white"
                        }
                    }
                    MouseArea {
                        id: hover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { power.open = false; modelData.act(); }
                    }
                }
            }
        }

        StatusOrb {
            width: 42 * root.s; height: width
            x: 1847 * root.s + (root.width - 1920 * root.s)
            y: 36 * root.s
            wifiStrength: root.connectivity.wifiStrength
            ethernet: root.connectivity.ethernet
            btEnabled: root.connectivity.btEnabled
            btSignal: root.connectivity.btSignal
            btDevices: root.connectivity.btDevices
            batteryLevel: Services.BatteryService.available ? Services.BatteryService.percentage : -1
            charging: Services.BatteryService.charging
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: root.height - 104 * root.s
            text: root.footer
            font.family: Config.appearance.ink ? Theme.fontUi : poppins.name
            font.weight: Config.appearance.ink ? Font.Medium : Font.DemiBold
            font.pixelSize: (Config.appearance.ink ? 15 : 40) * root.s
            color: Config.appearance.ink ? Theme.t2 : "white"
        }
    }

    // A round glass button with a Material Symbols glyph.
    component GlassCircle: Item {
        id: btn
        property string icon
        signal clicked()
        width: 64 * root.s; height: width

        LiquidGlass {
            anchors.fill: parent
            backgroundItem: wallpaper
            milk: 0.06
            outline: 0.7
            shapeRadius: width / 2
            tint: Qt.rgba(0.06, 0.02, 0.1, 0.25)
            Rectangle { anchors.fill: parent; radius: width / 2; color: "white" }
        }
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Qt.rgba(1, 1, 1, btnArea.pressed ? 0.15 : 0)
        }
        Text {
            anchors.centerIn: parent
            text: btn.icon
            font.family: "Material Symbols Rounded"
            font.pixelSize: 26 * root.s
            color: "white"
        }
        MouseArea {
            id: btnArea
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }

    Connections {
        target: root.context
        function onWrongPassword() { shakeAnim.restart(); }
    }

    // Keyboard focus, same rules as AsciiLockSurface: take it explicitly on
    // show and every time the lock window activates -- never rely on the
    // compositor's idea of the focused monitor (that once left the owner
    // typing into nothing). Keys that reach the root anyway still land in
    // the field.
    function _grabFocus() {
        if (root.interactive && root.visible) field.forceActiveFocus();
    }
    Component.onCompleted: Qt.callLater(_grabFocus)
    onVisibleChanged: _grabFocus()
    Connections {
        target: root.Window.window
        function onActiveChanged() {
            if (root.Window.window && root.Window.window.active) root._grabFocus();
        }
    }
    Keys.onPressed: event => {
        if (!root.interactive || root.busy) return;
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) row.submit();
        else if (event.key === Qt.Key_Backspace) field.text = field.text.slice(0, -1);
        else if (event.text && event.text >= " ") field.text += event.text;
        else return;
        field.forceActiveFocus();
        event.accepted = true;
    }

    // Unlock: fade the UI, then hand back to the context.
    states: State {
        when: root.context.state === root.context.unlocking
        PropertyChanges { ui.opacity: 0; ui.scale: 1.04 }
    }
    transitions: Transition {
        SequentialAnimation {
            NumberAnimation { properties: "opacity,scale"; duration: 380; easing.type: Easing.InCubic }
            ScriptAction { script: root.context.finishUnlockAnimation() }
        }
    }
}
