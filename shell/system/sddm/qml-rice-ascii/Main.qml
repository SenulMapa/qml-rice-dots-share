// ╭──────────────────────────────────────────────────────────────────────────╮
// │   M A I N                                                                │
// │   qml-rice-ascii · sddm login screen matching lock/AsciiLockSurface.qml  │
// ╰──────────────────────────────────────────────────────────────────────────╯
//
// The ASCII lock's waving, mouse-tilted, hue-rotating clock (see
// components/AsciiClock.qml, a self-contained port of that shader pipeline),
// plus the SDDM greeter chrome every login theme needs: user, password,
// session, power. No Quickshell, no shell Theme singleton -- this runs as
// the `sddm` user, which cannot read the owner's home directory at all, so
// every colour/font below is either a hardcoded dark fallback or read from
// the `config` context object (theme.conf's [General] section), which
// scripts/install-sddm-ascii-theme.sh populates from the owner's live
// wallpaper palette at install time. See that script's header for exactly
// which keys it writes.
//
// SDDM instantiates one Main.qml PER SCREEN (see the existing
// system/sddm/qml-rice/Main.qml -- it never Repeaters over screenModel
// itself, because SDDM's own greeter process already gives each screen its
// own window running this same file). `primaryScreen` is a context property
// SDDM sets per-window (see the commented-out `visible: primaryScreen` in
// /usr/share/sddm/themes/maldives/Main.qml and .../elarun/Main.qml) -- true
// only in the window on the primary monitor. The clock+date render on every
// screen; the password field, session picker and power row are gated to
// primaryScreen so they only ever appear once.

import QtQuick
import "components"

Item {
    id: root

    readonly property bool isPrimary:
        typeof primaryScreen !== "undefined" ? primaryScreen : true

    // ---- palette: config.* (theme.conf, baked in at install time) with the
    // same dark fallbacks as components/AsciiClock.qml's own defaults ------
    readonly property color colorSurface: _cfg("ColorSurface", "#0b0e10")
    readonly property color colorSurfaceText: _cfg("ColorSurfaceText", "#e7eef0")
    readonly property color colorSurfaceVariantText: _cfg("ColorSurfaceVariantText", "#a7b4b6")
    readonly property color colorError: _cfg("ColorError", "#ffb4ab")
    readonly property color colorWarning: _cfg("ColorWarning", "#f4c46b")
    readonly property color colorTertiary: _cfg("ColorTertiary", "#9eccf1")
    readonly property bool backgroundEnabled:
        String(config.BackgroundEnabled) === "true"
    readonly property string backgroundImage:
        config.BackgroundImage !== undefined ? config.BackgroundImage : ""

    function _cfg(key, fallback) {
        const v = config[key]
        return (v !== undefined && v !== "") ? v : fallback
    }

    // JetBrains Mono is system-installed (verified via fc-list at build
    // time, see scripts/install-sddm-ascii-theme.sh's header) -- safe to use
    // unconditionally for the ascii glyphs. Instrument Serif (the lock's
    // `Theme.fontDisplay`) is NOT system-wide (it lives under the owner's
    // ~/.local/share/fonts, unreadable by the sddm user), so the theme ships
    // its own copy in fonts/ -- see displayFont below.
    readonly property string fontMono: "JetBrains Mono"
    // Bundled with the theme: the sddm user can't read ~/.local/share/fonts,
    // where the lock's Instrument Serif lives. Falls back to generic serif
    // until (or unless) the file loads.
    FontLoader { id: displayFont; source: Qt.resolvedUrl("fonts/InstrumentSerif-Regular.ttf") }
    readonly property string fontDisplay: displayFont.status === FontLoader.Ready ? displayFont.font.family : "serif"

    anchors.fill: parent
    focus: true

    Rectangle {
        anchors.fill: parent
        color: root.colorSurface
        visible: !root.backgroundEnabled || root.backgroundImage === ""
    }

    // Optional dimmed/blurred wallpaper -- default OFF (BackgroundEnabled
    // defaults to "false" in theme.conf; the lock itself uses a flat bg, so
    // this stays off unless explicitly turned on at install time). No
    // QtGraphicalEffects/Qt5Compat dependency: the "blur" is a cheap
    // downscale-then-smooth-upscale (sourceSize far below the item size,
    // smooth: true), which avoids pulling in another module just for an
    // off-by-default extra.
    Image {
        id: bgImage
        anchors.fill: parent
        visible: root.backgroundEnabled && root.backgroundImage !== ""
        source: root.backgroundImage !== "" ? Qt.resolvedUrl(root.backgroundImage) : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        smooth: true
        sourceSize.width: 64
        sourceSize.height: Math.round(64 * (root.height / Math.max(root.width, 1)))
    }
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: root.backgroundEnabled && root.backgroundImage !== "" ? 0.55 : 0
    }

    // ---- clock / date -------------------------------------------------
    property date now: new Date()
    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }
    readonly property string clockText: Qt.formatDateTime(root.now, "HH:mm")
    readonly property string dateStr: Qt.formatDateTime(root.now, "dddd d MMMM")

    // ---- mouse tilt + hue -- identical math to lock/AsciiLockSurface.qml,
    // shared by every AsciiClock instance on this window (there's only ever
    // one per window, since one Main.qml == one screen). ------------------
    property real _mouseX: root.width / 2
    property real _mouseY: root.height / 2
    property bool _mouseInside: false
    property real _targetRotX: 0
    property real _targetRotY: 0
    property real _targetHue: 0
    property real _rotX: 0
    property real _rotY: 0
    property real _hue: 0
    property real _seconds: 0

    function _map(v, inMin, inMax, outMin, outMax) {
        const t = (v - inMin) / (inMax - inMin)
        return outMin + t * (outMax - outMin)
    }

    function _recomputeTargets() {
        if (root._mouseInside && root.width > 0 && root.height > 0) {
            root._targetRotX = root._map(root._mouseY, 0, root.height, 0.5, -0.5) * 0.6
            root._targetRotY = root._map(root._mouseX, 0, root.width, -0.5, 0.5) * 0.6
            root._targetHue = Math.atan2(
                root._mouseY - root.height / 2, root._mouseX - root.width / 2)
        } else {
            root._targetRotX = 0
            root._targetRotY = 0
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        hoverEnabled: true
        onPositionChanged: mouse => {
            root._mouseX = mouse.x
            root._mouseY = mouse.y
            root._recomputeTargets()
        }
        onContainsMouseChanged: {
            root._mouseInside = containsMouse
            root._recomputeTargets()
        }
    }

    readonly property real _rotTau: -1 / (60 * Math.log(1 - 0.05))
    readonly property real _hueTau: -1 / (60 * Math.log(1 - 0.075))

    FrameAnimation {
        id: frameAnim
        running: root.visible
        onTriggered: {
            const dt = frameAnim.frameTime > 0 ? frameAnim.frameTime : 0.016
            root._seconds += dt

            const rotFactor = 1 - Math.exp(-dt / root._rotTau)
            root._rotX += (root._targetRotX - root._rotX) * rotFactor
            root._rotY += (root._targetRotY - root._rotY) * rotFactor

            const hueFactor = 1 - Math.exp(-dt / root._hueTau)
            let dh = root._targetHue - root._hue
            while (dh > Math.PI) dh -= 2 * Math.PI
            while (dh < -Math.PI) dh += 2 * Math.PI
            root._hue += dh * hueFactor
        }
    }

    // ---- content layout: same ~60/40 vertical split as the lock ---------
    readonly property int contentTop: Math.round(root.height * 0.08)
    readonly property int contentHeight: Math.round(root.height * 0.84)
    readonly property int bottomZoneTop: root.contentTop + Math.round(root.contentHeight * 0.60)
    readonly property int bottomZoneHeight: root.contentHeight - Math.round(root.contentHeight * 0.60)

    AsciiClock {
        id: asciiClock
        x: 0
        y: root.contentTop
        width: root.width
        height: Math.round(root.contentHeight * 0.60)

        seconds: root._seconds
        rotX: root._rotX
        rotY: root._rotY
        hue: root._hue

        clockText: root.clockText
        fontMono: root.fontMono
        colorA: root.colorError
        colorB: root.colorWarning
        colorC: root.colorTertiary
        fallbackTextColor: root.colorSurfaceText
    }

    Text {
        id: dateText
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.bottomZoneTop + Math.round(root.bottomZoneHeight * 0.10)
        text: root.dateStr
        color: root.colorSurfaceText
        opacity: 0.8
        font.family: root.fontDisplay
        font.pixelSize: Math.max(22, Math.round(root.height * 0.028))
    }

    // ---- user: defaults to userModel.lastUser; click cycles when there is
    // more than one account (a quiet text toggle, not a picker sheet -- the
    // brief asks for exactly that on a single-user machine). ---------------
    property int userIndex: userModel.lastIndex >= 0 ? userModel.lastIndex : 0

    Instantiator {
        id: userRows
        model: userModel
        delegate: QtObject {
            required property string name
            required property string realName
        }
    }
    readonly property int userCount: userRows.count
    readonly property var currentUser: userRows.count > 0
        ? userRows.objectAt(Math.max(0, Math.min(root.userIndex, userRows.count - 1)))
        : null
    readonly property string userName: root.currentUser !== null ? root.currentUser.name : ""
    readonly property string userLabel: root.currentUser !== null
        ? (root.currentUser.realName !== "" ? root.currentUser.realName : root.currentUser.name)
        : ""

    Text {
        id: userText
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.bottomZoneTop + Math.round(root.bottomZoneHeight * 0.30)
        text: root.userLabel
        color: root.colorSurfaceVariantText
        opacity: 0.75
        font.family: root.fontDisplay
        font.pixelSize: Math.max(16, Math.round(root.height * 0.017))
        visible: root.isPrimary

        MouseArea {
            anchors.fill: parent
            enabled: root.userCount > 1
            cursorShape: root.userCount > 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                root.userIndex = (root.userIndex + 1) % root.userCount
                passwordField.clear()
                loginFailed = false
                loginMessage = ""
                passwordField.claim()
            }
        }
    }

    // ---- password ---------------------------------------------------------
    property bool authenticating: false
    property bool loginFailed: false
    property string loginMessage: ""

    function attempt(password) {
        if (root.authenticating || root.userName === "")
            return
        root.authenticating = true
        root.loginFailed = false
        root.loginMessage = ""
        sddm.login(root.userName, password, sessionPicker.currentIndex)
    }

    Connections {
        target: sddm
        function onLoginSucceeded() {
            root.authenticating = false
            root.loginMessage = ""
        }
        function onLoginFailed() {
            root.authenticating = false
            root.loginFailed = true
            root.loginMessage = qsTr("Wrong password")
            passwordField.clear()
        }
        function onInformationMessage(message) {
            root.loginMessage = message
        }
    }

    PasswordField {
        id: passwordField
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.bottomZoneTop + Math.round(root.bottomZoneHeight * 0.55)
        visible: root.isPrimary

        authenticating: root.authenticating
        failed: root.loginFailed
        message: root.loginMessage
        capsLock: typeof keyboard !== "undefined" ? keyboard.capsLock : false

        textColor: root.colorSurfaceText
        mutedColor: root.colorSurfaceVariantText
        badColor: root.colorError
        warnColor: root.colorWarning
        fontFamily: root.fontDisplay

        onSubmitted: password => root.attempt(password)
        onDismissed: {
            root.loginFailed = false
            root.loginMessage = ""
        }

        Component.onCompleted: passwordField.claim()
    }

    // ---- session: small text, cycles through sessionModel on click -------
    property int sessionIndex: sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0

    Instantiator {
        id: sessionRows
        model: sessionModel
        delegate: QtObject { required property string name }
    }
    readonly property int sessionCount: sessionRows.count

    QtObject {
        id: sessionPicker
        readonly property int currentIndex: root.sessionIndex
        readonly property string name: sessionRows.count > 0
            ? sessionRows.objectAt(
                Math.max(0, Math.min(root.sessionIndex, sessionRows.count - 1))).name
            : ""
    }

    function cycleSession() {
        if (root.sessionCount > 1)
            root.sessionIndex = (root.sessionIndex + 1) % root.sessionCount
    }

    Text {
        anchors.right: parent.right
        anchors.rightMargin: Math.round(root.width * 0.02)
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Math.round(root.height * 0.025)
        visible: root.isPrimary
        text: sessionPicker.name
        color: root.colorSurfaceVariantText
        opacity: 0.7
        font.family: root.fontDisplay
        font.pixelSize: 13

        MouseArea {
            anchors.fill: parent
            cursorShape: root.sessionCount > 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: root.cycleSession()
        }
    }

    // ---- power: quiet text buttons, no boxes -------------------------------
    Row {
        anchors.left: parent.left
        anchors.leftMargin: Math.round(root.width * 0.02)
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Math.round(root.height * 0.025)
        spacing: 18
        visible: root.isPrimary

        Text {
            text: qsTr("Restart")
            visible: sddm.canReboot
            color: root.colorSurfaceVariantText
            opacity: rebootArea.containsMouse ? 1 : 0.6
            font.family: root.fontDisplay
            font.pixelSize: 13
            Behavior on opacity { NumberAnimation { duration: 120 } }

            MouseArea {
                id: rebootArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: sddm.reboot()
            }
        }

        Text {
            text: qsTr("Shut down")
            visible: sddm.canPowerOff
            color: root.colorSurfaceVariantText
            opacity: powerArea.containsMouse ? 1 : 0.6
            font.family: root.fontDisplay
            font.pixelSize: 13
            Behavior on opacity { NumberAnimation { duration: 120 } }

            MouseArea {
                id: powerArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: sddm.powerOff()
            }
        }
    }

    // ---- keyboard: focus starts on the password field; Tab cycles the
    // session, matching the "on click or with a key" brief. -----------------
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Tab) {
            root.cycleSession()
            event.accepted = true
        }
    }

    // Test-only hook, same pattern as PasswordField.qml's debugInput: a
    // headless harness reaches the real TextInput through here instead of
    // needing a synthetic key-event pipeline.
    readonly property alias debugPasswordInput: passwordField.debugInput

    Component.onCompleted: passwordField.claim()
}
