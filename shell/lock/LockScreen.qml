pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import "../desktop/services" as Desk
import "../services"

/**
 * LockScreen -- WlSessionLock plus one lock/LockSurface.qml per screen.
 * NOT instantiated anywhere yet: shell.qml wiring and the `quickshell:lock`
 * shortcut are a later phase. This file is self-contained and inert until
 * something creates it.
 *
 * Mirrors the working pattern in ~/.config/quickshell/end4-pC/modules/
 * common/panels/lock/LockScreen.qml: one shared lock/LockContext.qml (so a
 * password typed on any monitor unlocks every surface at once), and a
 * Component handed to WlSessionLock.surface that Quickshell instantiates
 * once per screen automatically.
 *
 * Security fallback: if WlSessionLock ever reports it could not lock the
 * session securely (`secure` goes false while `locked` is true), this
 * forwards that to LockContext.failedToLock via reportLockFailure() rather
 * than silently leaving the user in front of an insecure lock. The wiring
 * phase decides what to do with that signal (fall back to hyprlock); this
 * file only raises it.
 *
 * Lock-surface routing (ascii-lock branch): `lockSurfaceComponent`'s
 * WlSessionLockSurface hosts its lock surface through a `Loader` keyed off
 * `DeskSettings.lockStyle` -- a string, "ascii" (default) | "classic" |
 * "impasto" -- instead of a hardcoded `LockSurface { ... }`. "ascii" loads
 * lock/AsciiLockSurface.qml (the waving-ASCII-clock surface built on
 * ReactBits' ASCIIText effect, replacing the impasto visual per the
 * owner's "we need to stop using impastos"); "impasto" loads lock/
 * ImpastoLockSurface.qml (blurred desktop, clock, avatar, password pill,
 * power row); anything else (including "classic" and any unrecognised
 * value) loads lock/LockSurface.qml. Every load goes through
 * `Loader.setSource(url, initialProperties)`, so a QML load error in the
 * target file (or anything it imports) surfaces as `Loader.status ===
 * Loader.Error` at RUNTIME instead of failing this whole file's static
 * type-check at compile time -- the fallback in `_onLoaderStatusChanged()`
 * below then reloads lock/LockSurface.qml the same way. All three
 * surfaces are bound to the SAME `lockContext`; only the impasto surface
 * also takes `lockShot`, the desktop-screenshot helper -- this gate only
 * ever changes which Item draws, never the PAM/session-lock plumbing
 * above it. The legacy `DeskSettings.lockImpasto` bool is no longer read
 * anywhere in this file.
 *
 * The screenshot the impasto surface blurs (lock/LockShot.qml, a straight
 * port of impasto's own services/LockService.qml grim-capture half) has to
 * finish BEFORE `sessionLock.locked` goes true: once locked, the
 * compositor blanks every output until the lock surface commits a buffer,
 * so a screenshot taken after that point would capture black. `lock()`
 * below therefore only flips `sessionLock.locked` inside `lockShot`'s
 * capture callback when the impasto surface is active; every other surface
 * (ascii, classic) needs no screenshot and keeps the original immediate-
 * lock behaviour, so LockShot.capture() is never even called for them.
 */
Scope {
    id: root

    property alias context: lockContext
    // Read-only escape hatches for the wiring layer (services/LockService.qml)
    // to poll without this file needing to know anything about fallback
    // policy itself -- it only ever raises context.failedToLock (see the
    // header comment) or lets the caller observe `secure` directly for its
    // own "didn't secure within N seconds" timeout.
    readonly property alias secure: sessionLock.secure
    readonly property alias locked: sessionLock.locked

    PamAuthenticator {
        id: pamAuth
    }

    LockContext {
        id: lockContext
        authenticator: pamAuth

        onStateChanged: {
            if (lockContext.state === lockContext.unlocked)
                root.unlock()
        }
    }

    // Screenshot helper for the impasto surface only -- see the header
    // comment above and lock/LockShot.qml's own header. Harmless to keep
    // instantiated even when DeskSettings.lockImpasto is false: nothing
    // calls capture() unless lock() below decides to.
    LockShot {
        id: lockShot
    }

    property Component lockSurfaceComponent: WlSessionLockSurface {
        id: sessionLockSurface
        color: "transparent"

        // Every surface shows the shared password pill and grabs keyboard
        // focus for itself -- see lock/LockSurface.qml's and
        // lock/ImpastoLockSurface.qml's own `focus: true` comments. We
        // deliberately do NOT gate this on "which monitor Hyprland thinks
        // is focused": that guess is exactly what left the owner typing
        // into nothing when the compositor's real focus target didn't
        // match it.
        Loader {
            id: surfaceLoader
            anchors.fill: parent

            function loadAscii(): void {
                surfaceLoader.setSource(
                    Qt.resolvedUrl("AsciiLockSurface.qml"),
                    { "context": lockContext })
            }

            function loadImpasto(): void {
                surfaceLoader.setSource(
                    Qt.resolvedUrl("ImpastoLockSurface.qml"),
                    { "context": lockContext, "shot": lockShot })
            }

            // Glass redesign (6 Oct 2026): the liquid-glass surface with the
            // 3D clock, playing the wallpaper video itself (gSlapper is
            // paused while locked -- see lock()/unlock()).
            function loadGlass(): void {
                const wp = WallpaperService.currentWallpaper;
                surfaceLoader.setSource(
                    Qt.resolvedUrl("GlassLockSurface.qml"),
                    {
                        "context": lockContext,
                        "videoSource": WallpaperService.currentWallpaperIsVideo ? "file://" + wp : "",
                        "stillSource": WallpaperService.currentStill ? "file://" + WallpaperService.currentStill : "",
                        "avatarSource": "file://" + Quickshell.env("HOME") + "/.face",
                        "userName": Quickshell.env("USER") || "",
                        "clock3d": true
                    })
            }

            Connections {
                target: surfaceLoader.item
                ignoreUnknownSignals: true
                function onSuspendRequested() { Quickshell.execDetached(["systemctl", "suspend"]) }
                function onRebootRequested() { Quickshell.execDetached(["systemctl", "reboot"]) }
                function onPoweroffRequested() { Quickshell.execDetached(["systemctl", "poweroff"]) }
            }

            function loadClassic(): void {
                surfaceLoader.setSource(
                    Qt.resolvedUrl("LockSurface.qml"),
                    { "context": lockContext })
            }

            Component.onCompleted: {
                if (Desk.DeskSettings.lockStyle === "impasto")
                    surfaceLoader.loadImpasto()
                else if (Desk.DeskSettings.lockStyle === "classic")
                    surfaceLoader.loadClassic()
                else if (Desk.DeskSettings.lockStyle === "glass")
                    surfaceLoader.loadGlass()
                else
                    surfaceLoader.loadAscii()
            }

            // Fallback mechanism (hard rule: "a load error in the new
            // surface falls back to the old surface"): `Loader.setSource`
            // above resolves ImpastoLockSurface.qml by URL at RUNTIME, so a
            // QML type/import error in that file (or in lock/AccountService.
            // qml / lock/ImpastoAvatar.qml / lock/ImpastoLockPower.qml /
            // lock/LockShot.qml, everything it pulls in) surfaces here as
            // `status === Loader.Error` instead of crashing this
            // statically-compiled file's own load. On that error this
            // switches to the classic lock/LockSurface.qml -- the exact
            // surface already shipping today -- by the same `setSource`
            // path, so the user is never left locked out behind a blank or
            // broken surface. Does not loop: LockSurface.qml is this
            // shell's proven, pre-existing surface and is never itself the
            // impasto path.
            onStatusChanged: {
                if (surfaceLoader.status === Loader.Error) {
                    console.warn("lock: ImpastoLockSurface failed to load, "
                        + "falling back to the classic lock surface")
                    surfaceLoader.loadClassic()
                }
            }
        }
    }

    WlSessionLock {
        id: sessionLock
        locked: false
        surface: root.lockSurfaceComponent

        onSecureStateChanged: {
            if (sessionLock.locked && !sessionLock.secure)
                lockContext.reportLockFailure()
        }
    }

    function lock(): void {
        lockContext.reset()
        // The impasto surface needs the desktop screenshot captured BEFORE
        // the compositor blanks the outputs -- see the header comment. The
        // ascii and classic surfaces draw a flat fill and never read
        // lockShot, so they keep the original immediate-lock behaviour
        // untouched -- LockShot.capture() is never even called for them.
        if (Desk.DeskSettings.lockStyle === "impasto") {
            lockShot.capture(() => { sessionLock.locked = true })
        } else {
            if (Desk.DeskSettings.lockStyle === "glass")
                root._wallpaperVideo("pause-video")
            sessionLock.locked = true
        }
    }

    // The glass lock plays the wallpaper itself; pause the desktop's video
    // backend meanwhile so only one decoder runs per screen.
    function _wallpaperVideo(cmd: string): void {
        const script = Qt.resolvedUrl("../scripts/wallpaperctl.sh").toString().replace("file://", "")
        Quickshell.execDetached([script, cmd])
    }

    function unlock(): void {
        // No reset() here: flipping state back to `locked` while the surface
        // is still mapped would flash the lock UI. lock() re-arms instead.
        sessionLock.locked = false
        if (Desk.DeskSettings.lockStyle === "impasto")
            lockShot.forget()
        // Not an unconditional resume-video: that restarted the wallpaper
        // video on battery (or under a fullscreen window) even though the
        // pause policy holds it there. Forget the per-output state the
        // explicit pause-video bypassed, so WallpaperService re-applies its
        // own policy to every output.
        if (Desk.DeskSettings.lockStyle === "glass") {
            WallpaperService.videoPausedOutputs = ({})
            WallpaperService.videoPauseDebounce.restart()
        }
    }
}
