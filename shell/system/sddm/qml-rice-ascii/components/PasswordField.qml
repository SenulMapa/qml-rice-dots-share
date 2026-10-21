// ╭──────────────────────────────────────────────────────────────────────────╮
// │   P A S S W O R D   F I E L D   ( A S C I I )                            │
// │   borderless password entry -- text + dots, identical style to          │
// │   lock/AsciiLockSurface.qml's passwordArea (no card/border anywhere).    │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick

Item {
    id: root

    property bool authenticating: false
    property bool failed: false
    property string message: ""
    property bool capsLock: false

    property color textColor: "#e7eef0"
    property color mutedColor: "#a7b4b6"
    property color badColor: "#ff453a"
    property color warnColor: "#ffd60a"
    property string fontFamily: "serif"

    signal submitted(string password)
    signal dismissed()

    function claim(): void { field.forceActiveFocus() }
    function clear(): void { field.clear() }

    // Test-only hook (see lock/AsciiLockSurface.qml's `debugAtlasSource` for
    // the established pattern): lets a headless harness drive the real
    // TextInput directly instead of needing a synthetic key-event pipeline.
    readonly property alias debugInput: field

    readonly property bool typing: field.text !== ""
        || root.authenticating
        || root.failed

    implicitWidth: 420
    implicitHeight: 96

    transform: Translate { id: shakeT; x: 0 }

    Text {
        id: promptText
        anchors.horizontalCenter: parent.horizontalCenter
        y: 0
        text: qsTr("Enter password")
        color: root.mutedColor
        font.family: root.fontFamily
        font.pixelSize: 20
        opacity: root.typing ? 0 : 0.65
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }

    Row {
        id: dotsRow
        anchors.horizontalCenter: parent.horizontalCenter
        y: 0
        spacing: 10
        opacity: root.typing ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 150 } }

        Repeater {
            model: Math.min(field.text.length, 24)
            delegate: Rectangle {
                width: 18; height: 18; radius: 9
                color: root.textColor
            }
        }

        Rectangle {
            id: caret
            visible: field.text.length === 0 && root.typing
            width: 3; height: 24
            color: root.textColor

            SequentialAnimation on opacity {
                running: caret.visible
                loops: Animation.Infinite
                NumberAnimation { to: 0; duration: 500 }
                NumberAnimation { to: 1; duration: 500 }
            }
        }
    }

    // Real (invisible) TextInput underneath: holds keyboard focus and the
    // actual password text; dotsRow above is purely decorative, exactly like
    // the lock's `context.currentText`-driven Repeater.
    TextInput {
        id: field
        anchors.fill: parent
        opacity: 0
        echoMode: TextInput.Password
        passwordCharacter: "*"
        passwordMaskDelay: 0
        enabled: !root.authenticating

        onAccepted: {
            if (field.text === "")
                return
            root.submitted(field.text)
        }

        onTextChanged: {
            if (root.failed && field.text !== "")
                root.dismissed()
        }

        Keys.onEscapePressed: field.clear()
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: dotsRow.y + 40
        text: root.capsLock ? qsTr("Caps Lock is on") : root.message
        visible: text !== ""
        font.family: root.fontFamily
        font.pixelSize: 13
        font.weight: Font.DemiBold
        color: root.capsLock ? root.warnColor : root.badColor
    }

    // ---- fail shake -- identical timing to lock/AsciiLockSurface.qml's
    // shakeAnim -----------------------------------------------------------
    SequentialAnimation {
        id: shakeAnim
        NumberAnimation { target: shakeT; property: "x"; to: -10; duration: 60 }
        NumberAnimation { target: shakeT; property: "x"; to: 10; duration: 60 }
        NumberAnimation { target: shakeT; property: "x"; to: -8; duration: 60 }
        NumberAnimation { target: shakeT; property: "x"; to: 8; duration: 60 }
        NumberAnimation { target: shakeT; property: "x"; to: 0; duration: 60 }
    }

    onFailedChanged: if (root.failed) shakeAnim.restart()
}
