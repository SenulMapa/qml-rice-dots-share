import QtQuick

// Lock-on-leave policy, split out so it can be tested with a stub lock
// target. Presence only ever locks; nothing here (or anywhere in the phone
// code) unlocks.
QtObject {
    id: root

    property bool enabled: false
    property var isLocked: function() { return false }
    property var lock: function() {}

    function onPresence(near: bool): bool {
        if (near || !enabled || isLocked())
            return false
        lock()
        return true
    }
}
