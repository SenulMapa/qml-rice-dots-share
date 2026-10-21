import QtQuick

/**
 * ArmState -- the "press once to arm, press again within a window to fire"
 * state machine shared by panels/SessionPage.qml (Hibernate/Log out/Restart/
 * Shut down tiles) and panels/ClipboardPage.qml ("Clear all"). A single
 * instance holds AT MOST one armed key at a time, so arming a second key
 * disarms the first for free -- there is nothing to clear on the old key,
 * its armed-ness was never anything but `armedKey === thatKey`.
 *
 * Pure and clock-injectable: `now` defaults to the wall clock but
 * test-armstate.qml overrides it with a manually-advanced fake instead of
 * sleeping for a real 3 seconds. There is no QML Timer in this file at all --
 * the caller owns a short-interval Timer that calls checkExpiry() while
 * something is armed (see panels/SessionPage.qml), which is also what keeps
 * this file trivially unit-testable outside a running shell.
 */
QtObject {
    id: root

    property int window: 3000
    property string armedKey: ""
    property real armedAt: 0
    // Overridable clock -- see test-armstate.qml.
    property var now: function () { return Date.now() }

    signal fired(string key)

    readonly property bool hasArmed: armedKey.length > 0

    function isArmed(key: string): bool {
        return armedKey === key
    }

    // Returns true when this press FIRED the action (caller should run it).
    // requiresConfirmation:false fires on the very first press -- the "safe"
    // actions (Lock, Suspend) never arm at all, they just fire.
    function press(key: string, requiresConfirmation: bool): bool {
        if (!requiresConfirmation) {
            armedKey = ""
            fired(key)
            return true
        }
        if (armedKey === key && (now() - armedAt) <= window) {
            armedKey = ""
            fired(key)
            return true
        }
        armedKey = key
        armedAt = now()
        return false
    }

    // Visual-only arming for the preview IPC (services/PreviewService.qml):
    // this never fires, so a preview call can never execute a real action.
    function arm(key: string): void {
        armedKey = key
        armedAt = now()
    }

    function disarm(): void {
        armedKey = ""
    }

    // Caller-driven expiry check -- see the header comment above.
    function checkExpiry(): void {
        if (hasArmed && (now() - armedAt) > window)
            armedKey = ""
    }
}
