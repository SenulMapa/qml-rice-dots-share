import QtQuick
import "../components"
import "../core"

/**
 * MacCallCard -- the Tahoe incoming-call banner (spec 3.6), compact. One row
 * of the banner height: avatar, caller name over the subtitle, and the
 * decline and answer buttons on the right of that same row. Same width and
 * light glass as the banners. Content only: the window is MacCallWindow.qml,
 * so the render harness can draw it directly.
 */
Item {
    id: root

    property var call: null
    property string error: ""
    // true while the call is ringing: the card slides and fades in, and out
    // again when it stops (the caller keeps the last call while it leaves).
    property bool live: true

    signal answerRequested()
    signal declineRequested()

    readonly property string title: call ? (call.name || call.number || "Unknown") : ""
    readonly property string initial: title.length > 0 ? title.charAt(0).toUpperCase() : "?"
    readonly property real pad: MacTokens.s(MacTokens.callPadding)
    readonly property real avatar: MacTokens.s(MacTokens.callAvatarSize)
    readonly property real buttonD: MacTokens.s(MacTokens.callButtonDiameter)
    readonly property real gap: MacTokens.s(MacTokens.callButtonGap)

    opacity: live ? 1 : 0
    Behavior on opacity {
        NumberAnimation { duration: MacTokens.callSlideMs; easing.type: Easing.OutCubic }
    }
    transform: Translate {
        x: root.live ? 0 : root.width * 0.25
        Behavior on x { NumberAnimation { duration: MacTokens.callSlideMs; easing.type: Easing.OutCubic } }
    }

    TahoeSurface {
        anchors.fill: parent
        kind: "call"
        radius: MacTokens.s(MacTokens.callRadius)
        tintAlpha: MacTokens.frostTintAlpha
    }

    // Avatar circle with the initial, left, vertically centred.
    Rectangle {
        id: avatarCircle
        x: root.pad
        y: (root.height - height) / 2
        width: root.avatar
        height: root.avatar
        radius: width / 2
        color: MacTokens.accentBlue

        Text {
            anchors.centerIn: parent
            text: root.initial
            color: MacTokens.accentOn
            font.family: MacTokens.displayFamily
            font.pixelSize: root.avatar * 0.46
            font.weight: Font.DemiBold
        }
    }

    // Answer (green) at the far right, decline (red) left of it.
    Rectangle {
        id: answer
        objectName: "answer"
        width: root.buttonD
        height: root.buttonD
        radius: width / 2
        x: root.width - root.pad - width
        y: (root.height - height) / 2
        color: MacTokens.callAnswer
        scale: answerTap.pressed ? 0.92 : 1
        Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

        Icon {
            anchors.centerIn: parent
            name: "phone"
            size: answer.width * 0.5
            color: "#ffffff"
        }
        TapHandler { id: answerTap; onTapped: root.answerRequested() }
    }

    Rectangle {
        id: decline
        objectName: "decline"
        width: root.buttonD
        height: root.buttonD
        radius: width / 2
        x: answer.x - root.gap - width
        y: (root.height - height) / 2
        color: MacTokens.callDecline
        scale: declineTap.pressed ? 0.92 : 1
        Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

        Icon {
            anchors.centerIn: parent
            name: "phone"
            size: decline.width * 0.5
            color: "#ffffff"
            rotation: 135
        }
        TapHandler { id: declineTap; onTapped: root.declineRequested() }
    }

    // Name over subtitle, between the avatar and the buttons.
    Column {
        x: avatarCircle.x + avatarCircle.width + root.gap
        y: (root.height - height) / 2
        width: decline.x - root.gap - x
        spacing: 1

        Text {
            width: parent.width
            text: root.title
            color: MacTokens.labelPrimary
            elide: Text.ElideRight
            maximumLineCount: 1
            textFormat: Text.PlainText
            font.family: MacTokens.textFamily
            font.pixelSize: MacTokens.s(MacTokens.callNameSize)
            font.weight: Font.DemiBold
        }

        Text {
            width: parent.width
            text: root.error !== "" ? root.error : "iPhone · mobile"
            color: root.error !== "" ? MacTokens.criticalFill : MacTokens.labelSecondary
            elide: Text.ElideRight
            maximumLineCount: 1
            textFormat: Text.PlainText
            font.family: MacTokens.textFamily
            font.pixelSize: MacTokens.s(MacTokens.callSubtitleSize)
        }
    }
}
