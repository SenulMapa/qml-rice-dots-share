// DEV/TEST-ONLY entry point. NEVER installed (install.sh does not copy this
// file or FakeGreetdContext.qml -- see both files' own headers). Renders
// the exact same lock/AsciiLockSurface.qml the real greeter.qml hosts, but
// windowed (FloatingWindow, not a layershell overlay) and driven by
// FakeGreetdContext.qml instead of GreetdContext.qml, so this can run
// safely inside an existing desktop session for visual comparison against
// the real greeter -- no real greetd session, no Greetd singleton import
// anywhere in the dependency chain.
//
// Refuses to do anything unless QMLRICE_GREETER_TEST=1 is set, as a second
// belt-and-suspenders guard on top of "this file is simply never
// installed" -- run it as:
//
//   QMLRICE_GREETER_TEST=1 qs -p greeter-test.qml
//
// Same IPC-preview shape as ../../preview-lock.qml (this repo's own
// established pattern for exercising a lock surface's auth flow without
// real input-injection tooling):
//
//   qs -c <instance> ipc call greetertest submit test    # succeeds
//   qs -c <instance> ipc call greetertest submit wrong    # fails, shake
//   qs -c <instance> ipc call greetertest reset
import QtQuick
import Quickshell
import Quickshell.Io

FloatingWindow {
    id: window
    title: "greetd greeter test"
    implicitWidth: 1920
    implicitHeight: 1080

    readonly property bool testModeEnabled: Quickshell.env("QMLRICE_GREETER_TEST") === "1"

    // See greeter.qml's own header for why this is a Loader against an
    // absolute file:// URL rather than a static `import "../../lock"` --
    // quickshell's `-p <file>` sandbox blackholes relative parent-directory
    // imports past this file's own containing directory.
    readonly property string shellRoot:
        Quickshell.env("QMLRICE_SHELL_ROOT") || "/usr/share/qml-rice-greeter/shell"
    readonly property url asciiLockSurfaceUrl:
        "file://" + window.shellRoot + "/lock/AsciiLockSurface.qml"

    Rectangle {
        anchors.fill: parent
        color: "#202027"
    }

    FakeGreetdContext {
        id: fakeContext
    }

    Loader {
        anchors.fill: parent
        visible: window.testModeEnabled
        active: window.testModeEnabled

        Component.onCompleted: {
            if (window.testModeEnabled)
                setSource(window.asciiLockSurfaceUrl, { "context": fakeContext })
        }

        onStatusChanged: {
            if (status === Loader.Error)
                console.warn("greeter-test: failed to load AsciiLockSurface from",
                    window.asciiLockSurfaceUrl)
        }
    }

    Text {
        anchors.centerIn: parent
        visible: !window.testModeEnabled
        text: "Refusing to run: set QMLRICE_GREETER_TEST=1"
        color: "white"
        font.pixelSize: 24
    }

    // Quits instead of launching anything on success -- there is nothing
    // to launch in test mode, and this file never imports the real
    // GreetdContext/Greetd service at all. Waits for AsciiLockSurface to
    // actually call finishUnlockAnimation() (state -> unlocked) rather than
    // quitting the instant auth succeeds, so the unlock animation is seen
    // to completion instead of being cut short.
    Connections {
        target: fakeContext
        function onStateChanged() {
            if (fakeContext.state === fakeContext.unlocked)
                quitTimer.start()
        }
    }
    Timer {
        id: quitTimer
        interval: 250
        onTriggered: Qt.quit()
    }

    IpcHandler {
        target: "greetertest"

        function submit(password: string): void {
            fakeContext.submit(password)
        }

        function reset(): void {
            fakeContext.currentText = ""
            fakeContext.state = fakeContext.locked
        }
    }
}
