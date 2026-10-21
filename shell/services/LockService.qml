pragma Singleton
import QtQuick
import Quickshell

/**
 * LockService -- the single policy point for "engage the lock": always try
 * our own lock/LockScreen.qml first, fall back to hyprlock only if it
 * reports lock/LockContext.qml's failedToLock signal, or never becomes
 * `secure` within 2 seconds. Both real entry points --
 * core/ShellCompatShortcuts.qml's `quickshell:lock` global shortcut and
 * services/SessionService.qml's "lock" action (which is also what the
 * `session` IPC target's lock() and the Session page's lock tile both run
 * through) -- call engage() here instead of deciding the fallback
 * themselves, so there is exactly one fallback policy for the whole shell.
 *
 * lockScreen is registered once by shell.qml, right after it instantiates
 * lock/LockScreen.qml -- this service holds no Wayland object itself, only
 * orchestrates the one shell.qml owns. Only three members of it are ever
 * touched: lock()/unlock(), `locked`, `secure`, and `context.failedToLock`
 * -- exactly lock/LockScreen.qml's public surface -- so a plain fake object
 * exposing that same shape (see test-lock.qml) can stand in for it without
 * any real Wayland/session-lock object existing, for testing this file's
 * fallback decision in isolation.
 *
 * fallbackLauncher is injectable for the same reason lock/LockContext.qml's
 * `authenticator` is: test-lock.qml swaps it out so the fallback DECISION
 * (did we fall back, and when) can be asserted without ever actually
 * running hyprlock.
 */
QtObject {
    id: root

    property QtObject lockScreen: null
    // True from the moment engage() calls lockScreen.lock() until either the
    // lock secures, fails, or the 2s timeout gives up on it.
    property bool pending: false

    // Real fallback: guarded the same way core/ShellCompatShortcuts.qml's
    // own hyprlock fallback already is, so a concurrent manual hyprlock
    // launch doesn't double-fire.
    property var fallbackLauncher: function() {
        Quickshell.execDetached(["sh", "-c", "pidof hyprlock >/dev/null || hyprlock"])
    }

    function registerLockScreen(screen): void {
        root.lockScreen = screen
        if (!screen)
            return
        if (screen.context && screen.context.failedToLock)
            screen.context.failedToLock.connect(root._onFailedToLock)
        if (screen.secureChanged)
            screen.secureChanged.connect(root._onSecureChanged)
    }

    function engage(): void {
        if (root.pending)
            return
        if (root.lockScreen && root.lockScreen.locked)
            return
        if (!root.lockScreen) {
            root._fallback()
            return
        }
        root.pending = true
        root.lockScreen.lock()
        secureTimeout.restart()
    }

    function _onFailedToLock(): void {
        if (!root.pending)
            return
        root._fallback()
    }

    function _onSecureChanged(): void {
        if (root.pending && root.lockScreen && root.lockScreen.secure) {
            root.pending = false
            secureTimeout.stop()
        }
    }

    function _fallback(): void {
        root.pending = false
        secureTimeout.stop()
        if (root.lockScreen && root.lockScreen.locked)
            root.lockScreen.unlock()
        root.fallbackLauncher()
    }

    property Timer secureTimeout: Timer {
        interval: 2000
        repeat: false
        onTriggered: {
            if (root.pending && root.lockScreen && !root.lockScreen.secure)
                root._fallback()
            else
                root.pending = false
        }
    }
}
