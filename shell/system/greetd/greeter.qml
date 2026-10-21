//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

/**
 * greeter.qml -- PRODUCTION greetd greeter entry point. Hosts the exact
 * same lock/AsciiLockSurface.qml the live desktop shell's lock screen uses
 * (loaded here, never reimplemented -- see AsciiLockSurface.qml's own
 * header), one instance per screen via Variants/PanelWindow exactly like
 * the previous /etc/greetd/quickshell-greeter/shell.qml did, but bound to
 * GreetdContext.qml (this directory) instead of a real WlSessionLock +
 * LockContext, since there is no session to lock yet -- greetd itself is
 * the authentication boundary.
 *
 * Loading mechanism (NOT a static `import "../../lock"`): Quickshell's
 * `-p <file>` mode sandboxes every STATIC relative import to the entry
 * file's own containing directory (proven empirically -- `import
 * "../../lock"` from this file gets the parent traversal silently
 * "blackholed" by quickshell's qs:@ URL interceptor, surfacing as
 * "AsciiLockSurface is not a type" with no other explanation). Loading it
 * through a `Loader` with an absolute `file://` source URL instead
 * bypasses that sandboxed scheme entirely -- proven by probing a throwaway
 * Loader against lock/LockSurface.qml, which loaded successfully (got as
 * far as its own "required property context" QML warning) the same way.
 * AsciiLockSurface.qml's OWN internal relative imports ("../core", "../
 * desktop/services") are resolved against ITS real file:// location once
 * loaded this way, completely unaffected by this file's sandboxed root --
 * exactly like lock/LockScreen.qml's own `Loader.setSource(Qt.resolvedUrl
 * (...))` pattern, just with an absolute path instead of a relative one.
 *
 * `shellRoot` is resolvable at both dev-tree and installed-tree layouts:
 * QMLRICE_SHELL_ROOT overrides it (used by local test invocations); the
 * default assumes install.sh's own target, /usr/share/qml-rice-greeter/
 * shell.
 *
 * Deliberately contains NO reference anywhere to QMLRICE_GREETER_TEST or
 * FakeGreetdContext.qml -- test mode lives entirely in the separate,
 * dev-only greeter-test.qml sitting next to this file, which install.sh
 * never copies into the installed tree. That means there is no code path
 * in this file, at any env var value, that can avoid a real greetd
 * session. See GreetdContext.qml's own header for the rest of the
 * security rationale.
 *
 * Single user, no picker: install.sh substitutes the target user into
 * GreetdContext's username property at installation time.
 * No session picker either -- launchCommand is hardcoded to
 * ["start-hyprland"].
 *
 * Readiness marker: once the first screen's surface has actually rendered
 * a frame (Window.frameSwapped, not just Component.onCompleted -- QML
 * "completed" fires before anything is on screen), this touches
 * $QMLRICE_GREETER_READY_FILE (default "$XDG_RUNTIME_DIR/qmlrice-greeter.
 * ready") at mode 0600. greeter-launch.sh polls for that file to decide
 * whether this greeter actually came up, instead of guessing off a fixed
 * timeout against process start.
 */
ShellRoot {
    id: root

    readonly property string shellRoot:
        Quickshell.env("QMLRICE_SHELL_ROOT") || "/usr/share/qml-rice-greeter/shell"
    readonly property url asciiLockSurfaceUrl:
        "file://" + root.shellRoot + "/lock/AsciiLockSurface.qml"
    // Glass redesign (6 Oct 2026): the liquid-glass surface is the greeter;
    // AsciiLockSurface stays as the fallback if it fails to load.
    readonly property url glassLockSurfaceUrl:
        "file://" + root.shellRoot + "/lock/GlassLockSurface.qml"
    // install.sh copies the owner's wallpaper (video or still) and avatar
    // here, readable by the greeter user.
    readonly property string mediaRoot: root.shellRoot + "/../media"

    readonly property string readyFilePath:
        (Quickshell.env("QMLRICE_GREETER_READY_FILE") || "")
            || (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qmlrice-greeter.ready"
    property bool readyMarkerWritten: false

    function markReady() {
        if (root.readyMarkerWritten) return
        root.readyMarkerWritten = true
        readyMarkProcess.command = ["sh", "-c",
            "touch " + JSON.stringify(root.readyFilePath)
            + " && chmod 600 " + JSON.stringify(root.readyFilePath)]
        readyMarkProcess.running = true
    }

    Process {
        id: readyMarkProcess
        onExited: (exitCode) => {
            if (exitCode !== 0)
                console.warn("greeter: failed to write readiness marker at",
                    root.readyFilePath)
        }
    }

    GreetdContext {
        id: greetdContext
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusiveZone: 0
            color: "transparent"

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            Loader {
                id: surfaceLoader
                anchors.fill: parent

                // AsciiLockSurface has a `required property QtObject
                // context` -- it must be supplied as an initial property at
                // construction time (setSource's second argument), exactly
                // like lock/LockScreen.qml's own Loader does, NOT assigned
                // after the fact in onLoaded (by then the required-property
                // check has already failed and the component is in Error
                // state).
                property bool triedGlass: false
                Component.onCompleted: {
                    triedGlass = true
                    surfaceLoader.setSource(root.glassLockSurfaceUrl, {
                        "context": greetdContext,
                        "clock3d": false,
                        "userName": greetdContext.username,
                        "videoSource": "file://" + root.mediaRoot + "/wallpaper.mp4",
                        "stillSource": "file://" + root.mediaRoot + "/wallpaper-still.png",
                        "avatarSource": "file://" + root.mediaRoot + "/avatar"
                    })
                }

                onStatusChanged: {
                    if (surfaceLoader.status !== Loader.Error)
                        return
                    if (triedGlass && surfaceLoader.source === root.glassLockSurfaceUrl) {
                        console.warn("greeter: GlassLockSurface failed, falling back to AsciiLockSurface")
                        surfaceLoader.setSource(root.asciiLockSurfaceUrl, { "context": greetdContext })
                    } else {
                        console.warn("greeter: failed to load AsciiLockSurface from",
                            root.asciiLockSurfaceUrl)
                    }
                }

                Connections {
                    target: surfaceLoader.item
                    ignoreUnknownSignals: true
                    function onSuspendRequested() { Quickshell.execDetached(["systemctl", "suspend"]) }
                    function onRebootRequested() { Quickshell.execDetached(["systemctl", "reboot"]) }
                    function onPoweroffRequested() { Quickshell.execDetached(["systemctl", "poweroff"]) }
                }
            }

            // frameSwapped lives on the underlying QQuickWindow, not on
            // Quickshell's PanelWindow -- declaring `onFrameSwapped` here
            // made the whole file fail to load ("Cannot assign to
            // non-existent property"), so the greeter never drew, never wrote
            // the marker, and greeter-launch.sh fell back after 20s on every
            // boot. Reach the real window through the Window attached
            // property, the same way desktop/Desktop.qml does.
            Connections {
                target: surfaceLoader.Window.window
                function onFrameSwapped(): void {
                    root.markReady()
                }
            }
        }
    }
}
