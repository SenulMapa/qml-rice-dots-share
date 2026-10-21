pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell

import "../desktop/services" as Desk
import "../desktop/components" as DeskComponents

/**
 * ported from impasto lock/LockSurface.qml, verbatim except:
 *   - Theme -> Desk.DeskTheme (impasto's theme/Theme.qml values, per the
 *     hard rules -- not this shell's own core/Theme.qml).
 *   - LockService (impasto's own PAM+screenshot singleton, services/
 *     LockService.qml) split into two pieces this shell keeps separate:
 *     the screenshot half is lock/LockShot.qml (`shot`, required property,
 *     handed in by lock/LockScreen.qml), the PAM/state-machine half is
 *     THIS SHELL'S PRE-EXISTING lock/LockContext.qml (`context`, required
 *     property) -- kept unchanged per the hard rule "keep the PAM path
 *     identical to ours". `LockService.authenticating`/`.failed` ->
 *     `context.state === context.authenticating`/`context.state ===
 *     context.failed`; `LockService.message` (a free string) doesn't exist
 *     on LockContext (only the `wrongPassword` signal), so `_message` below
 *     is a local property set from that signal instead -- same visual
 *     result (a red line under the field after a wrong password), sourced
 *     differently.
 *   - `submitted(password)` signal (impasto's LockScreen.qml wires it to
 *     LockService.submit) -> calls `context.submit(field.text)` directly,
 *     since this shell's LockContext exposes that as a function, not a
 *     signal to forward.
 *   - BatteryService/BatteryWidget -> this shell's own already-ported
 *     desktop/components/BatteryWidget.qml + desktop/services/
 *     DeskBatteryService.qml (from the earlier desktop-widgets port) --
 *     same shape, not re-ported a second time.
 *   - AccountService/Avatar -> lock/AccountService.qml + lock/
 *     ImpastoAvatar.qml (this round's own ports, see their own header
 *     comments for what changed).
 *   - SettingsService.clockFormat -> Desk.DeskSettings.clockFormat
 *     (already shipped by the desktop-widgets port, same "hh:mm" default).
 *   - SettingsService.lockBlur (a settings-panel slider, default 32) has no
 *     equivalent store here -- hardcoded to the same default (32) instead
 *     of wiring a new settings control, out of scope for this port.
 *   - RingIndicator -> this shell's own desktop/components/RingIndicator.qml
 *     (same file, already ported).
 *   - `refusal`/shake-on-failure: impasto's own LockService.failed is a
 *     plain settable bool, cleared the moment the user resumes typing. This
 *     shell's LockContext is a strict state machine (locked -> failed only
 *     returns to locked via `acknowledgeFailure()`), so the shake here
 *     calls `context.acknowledgeFailure()` on `onFinished` -- the same
 *     pattern this shell's own lock/LockSurface.qml already uses for its
 *     own shake -- instead of impasto's direct bool-clear-on-keystroke.
 *   - The unlock choreography (impasto: instant, both the surface and
 *     LockService.locked flip together) doesn't fit this shell's
 *     LockContext, which requires `finishUnlockAnimation()` to be called
 *     once *some* animation has actually played (see LockContext.qml's own
 *     header) before it will reach `unlocked`. This file plays a short
 *     220ms fade on `context.state === context.unlocking` and then calls
 *     `context.finishUnlockAnimation()` -- new, not upstream, but the
 *     smallest change that satisfies LockContext's contract.
 *
 * Not ported: impasto's own top-of-file signal `submitted(string password)`
 * (superseded by calling context.submit() directly, see above).
 */
Item {
    id: root

    required property QtObject context
    required property QtObject shot

    // Local stand-in for impasto's `LockService.message` -- see header.
    property string _message: ""

    focus: true

    // ── BACKGROUND ──────────────────────────────────────────────────────────

    Rectangle {
        anchors.fill: parent
        color: Desk.DeskTheme.island
    }

    Image {
        id: shotImage

        anchors.fill: parent
        source: root.shot.shotSource
        visible: false
        fillMode: Image.PreserveAspectCrop
        asynchronous: false
        cache: false
    }

    MultiEffect {
        anchors.fill: parent
        source: shotImage
        visible: shotImage.status === Image.Ready
        blurEnabled: true
        blur: 1
        // Enough to make text unreadable while the desktop stays
        // recognisable -- see header re: SettingsService.lockBlur.
        blurMax: 32
        // Barely darkened: a dark desktop dimmed further looks broken. The
        // text has its own shadow and every capsule is opaque, so the
        // background only needs to be blurred.
        brightness: -0.05
        saturation: 0
    }

    // The lightest of washes, for separation rather than contrast.
    Rectangle {
        anchors.fill: parent
        color: Desk.DeskTheme.scrim
        opacity: 0.18
    }

    // ── STATUS ──────────────────────────────────────────────────────────────
    //
    // The battery in the top corner, and nothing where the island goes, to
    // match the login screen.

    Rectangle {
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.top: parent.top
        anchors.topMargin: Desk.DeskTheme.barTopMargin
        width: Desk.DeskTheme.capsuleHeight
        height: Desk.DeskTheme.capsuleHeight
        radius: Desk.DeskTheme.radiusPill
        color: Desk.DeskTheme.island
        visible: Desk.DeskBatteryService.available

        DeskComponents.BatteryWidget {
            anchors.centerIn: parent
            size: Desk.DeskTheme.capsuleHeight
        }
    }

    // ── CLOCK ───────────────────────────────────────────────────────────────

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Item {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -60
        width: face.width
        height: face.height

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowBlur: 1
            shadowOpacity: 0.6
            shadowVerticalOffset: 2
            shadowColor: Desk.DeskTheme.island
        }

        Column {
            id: face

            spacing: 4

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDateTime(clock.date, Desk.DeskSettings.clockFormat)
                font.family: Desk.DeskTheme.fontFamily
                font.pixelSize: 92
                font.weight: Font.Light
                color: Desk.DeskTheme.text
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDateTime(clock.date, "dddd d MMMM")
                font.family: Desk.DeskTheme.fontFamily
                font.pixelSize: Desk.DeskTheme.fontSizeLarge
                color: Desk.DeskTheme.text
                opacity: 0.75
            }
        }
    }

    // ── USER ────────────────────────────────────────────────────────────────
    //
    // The avatar and name, between the clock and the field. From the
    // account unless overridden in the settings, which is the same source
    // the login screen reads. Shadowed like the clock.
    Item {
        id: who

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: entry.top
        anchors.bottomMargin: 26
        width: identity.width
        height: identity.height

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowBlur: 0.9
            shadowOpacity: 0.65
            shadowVerticalOffset: 2
            shadowColor: Desk.DeskTheme.island
        }

        Column {
            id: identity

            spacing: 12

            ImpastoAvatar {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 88
                height: 88
                source: AccountService.avatar
                initials: AccountService.initials
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: AccountService.name
                font.family: Desk.DeskTheme.fontFamily
                font.pixelSize: Desk.DeskTheme.fontSizeLarge
                font.weight: Font.DemiBold
                color: Desk.DeskTheme.text
            }
        }
    }

    // ── PASSWORD ────────────────────────────────────────────────────────────
    //
    // The field holds focus from the start but stays invisible until the
    // first key, with a prompt shown in its place. Hidden by opacity, not
    // `visible`: an invisible item cannot hold keyboard focus.
    Item {
        id: entry

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 104
        width: 360
        height: 96

        readonly property bool typing: field.text !== ""
            || root.context.state === root.context.authenticating
            || root.context.state === root.context.failed

        // ── PROMPT ──────────────────────────────────────────────────────────

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 12
            spacing: 10
            opacity: entry.typing ? 0 : 1
            visible: opacity > 0

            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowBlur: 0.8
                shadowOpacity: 0.7
                shadowColor: Desk.DeskTheme.island
            }

            Behavior on opacity {
                NumberAnimation { duration: Desk.DeskTheme.durationMedium; easing.type: Desk.DeskTheme.easing }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "󰌌"
                font.family: Desk.DeskTheme.fontMono
                font.pixelSize: 17
                color: Desk.DeskTheme.text
                opacity: 0.8
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Type your password to unlock"
                font.family: Desk.DeskTheme.fontFamily
                font.pixelSize: Desk.DeskTheme.fontSizeMedium
                color: Desk.DeskTheme.text
                opacity: 0.8
            }
        }

        // ── FIELD ───────────────────────────────────────────────────────────

        Rectangle {
            id: box

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            width: 320
            height: 50
            radius: Desk.DeskTheme.radiusPill
            // Pure black, like the island: over a photograph only an
            // opaque capsule reads as a surface.
            color: Desk.DeskTheme.island
            border.width: 1
            border.color: {
                if (root.context.state === root.context.failed)
                    return Desk.DeskTheme.indicatorBad
                return field.activeFocus ? Desk.DeskTheme.accent : Desk.DeskTheme.islandBorder
            }

            opacity: entry.typing ? 1 : 0
            // Scales in from 94%, so it reads as the prompt turning into
            // the field.
            scale: entry.typing ? 1 : 0.94

            Behavior on opacity {
                NumberAnimation { duration: Desk.DeskTheme.durationMedium; easing.type: Desk.DeskTheme.easing }
            }
            Behavior on scale {
                NumberAnimation { duration: Desk.DeskTheme.durationMedium; easing.type: Desk.DeskTheme.easing }
            }
            Behavior on border.color { ColorAnimation { duration: Desk.DeskTheme.durationFast } }

            // Shakes on a wrong password; the shake is seen before the
            // text below. onFinished acknowledges the failure back to
            // `locked` -- see header re: LockContext's strict state
            // machine.
            SequentialAnimation {
                id: refusal

                loops: 2
                NumberAnimation { target: box; property: "anchors.horizontalCenterOffset"
                    to: -9; duration: 55; easing.type: Easing.OutCubic }
                NumberAnimation { target: box; property: "anchors.horizontalCenterOffset"
                    to: 9; duration: 55; easing.type: Easing.OutCubic }
                NumberAnimation { target: box; property: "anchors.horizontalCenterOffset"
                    to: 0; duration: 55; easing.type: Easing.OutCubic }
                onFinished: root.context.acknowledgeFailure()
            }

            Connections {
                target: root.context
                function onStateChanged(): void {
                    if (root.context.state === root.context.failed) {
                        root._message = "Wrong password"
                        refusal.restart()
                    } else if (root.context.state === root.context.unlocking) {
                        root._beginUnlock()
                    }
                }
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 19
                anchors.verticalCenter: parent.verticalCenter
                text: "󰌾"
                font.family: Desk.DeskTheme.fontMono
                font.pixelSize: 15
                color: root.context.state === root.context.failed ? Desk.DeskTheme.indicatorBad : Desk.DeskTheme.textMuted

                Behavior on color { ColorAnimation { duration: Desk.DeskTheme.durationFast } }
            }

            TextInput {
                id: field

                anchors.left: parent.left
                anchors.leftMargin: 48
                anchors.right: parent.right
                anchors.rightMargin: 48
                anchors.verticalCenter: parent.verticalCenter

                echoMode: TextInput.Password
                passwordCharacter: "•"
                passwordMaskDelay: 0
                enabled: root.context.state !== root.context.authenticating
                    && root.context.state !== root.context.unlocking
                font.family: Desk.DeskTheme.fontFamily
                font.pixelSize: Desk.DeskTheme.fontSizeMedium
                color: Desk.DeskTheme.text
                selectionColor: Desk.DeskTheme.accent
                selectedTextColor: Desk.DeskTheme.accentText
                clip: true

                onAccepted: {
                    if (field.text === "")
                        return
                    root.context.submit(field.text)
                    field.clear()
                }

                // Typing clears the error text (the field itself already
                // accepts submit() again from `failed`, same as `locked` --
                // see LockContext.submit()'s own guard).
                onTextChanged: {
                    if (root.context.state === root.context.failed && field.text !== "")
                        root._message = ""
                }

                // Escape clears the field rather than leaving part of a
                // password on screen.
                Keys.onEscapePressed: field.clear()
            }

            // A spinner while PAM checks the password.
            Item {
                anchors.right: parent.right
                anchors.rightMargin: 17
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                height: 18
                visible: root.context.state === root.context.authenticating

                DeskComponents.RingIndicator {
                    id: spinner

                    anchors.fill: parent
                    thickness: 2
                    progress: 0.28
                    trackColor: "transparent"
                    fillColor: Desk.DeskTheme.accent

                    RotationAnimator {
                        target: spinner
                        running: root.context.state === root.context.authenticating
                        from: 0
                        to: 360
                        duration: 900
                        loops: Animation.Infinite
                    }
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: box.bottom
            anchors.topMargin: 14
            text: root._message
            visible: text !== ""
            font.family: Desk.DeskTheme.fontFamily
            font.pixelSize: Desk.DeskTheme.fontSizeSmall
            color: Desk.DeskTheme.indicatorBad
        }
    }

    // ── POWER ───────────────────────────────────────────────────────────────
    //
    // Bottom left at the bar's margin, where the login screen has the same
    // buttons.

    ImpastoLockPower {
        anchors.left: parent.left
        anchors.leftMargin: Desk.DeskTheme.barTopMargin + 6
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Desk.DeskTheme.barTopMargin + 6
    }

    // ── UNLOCK (new -- see header) ───────────────────────────────────────────

    Behavior on opacity {
        NumberAnimation { duration: 220; easing.type: Desk.DeskTheme.easing }
    }

    function _beginUnlock(): void {
        root.opacity = 0
        unlockTimer.restart()
    }

    // Gives the 220ms opacity Behavior above time to actually play before
    // handing control back to LockContext -- finishUnlockAnimation() is
    // what lets WlSessionLock.locked go false (see lock/LockScreen.qml's
    // onStateChanged -> root.unlock()).
    readonly property Timer unlockTimer: Timer {
        id: unlockTimer
        interval: 240
        onTriggered: root.context.finishUnlockAnimation()
    }

    visible: root.context.state !== root.context.unlocked

    // ── FOCUS ───────────────────────────────────────────────────────────────
    //
    // Every surface grabs keyboard focus for the password field the moment
    // it exists, on becoming visible, and whenever its Window becomes
    // active -- same reasoning as this shell's own lock/LockSurface.qml
    // (see that file's header): the compositor hands real key events to
    // whichever surface it considers focused, so every surface must be
    // armed.
    function _grabFocus(): void {
        field.forceActiveFocus()
    }

    onVisibleChanged: if (root.visible) root._grabFocus()

    Connections {
        target: root.Window.window
        function onActiveChanged() {
            if (root.Window.window && root.Window.window.active)
                root._grabFocus()
        }
    }

    Component.onCompleted: root._grabFocus()
}
