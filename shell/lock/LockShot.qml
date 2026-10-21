pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

// ported from impasto services/LockService.qml, verbatim except: this is
// only the screenshot half of that file (capture/shotSource/forget) -- the
// PAM/locked/authenticating/message half of LockService.qml is NOT ported,
// because this shell already has its own PAM/state machine in
// lock/LockContext.qml + lock/PamAuthenticator.qml, which the hard rules say
// to keep. Renamed LockShot to avoid colliding with this shell's own
// services/LockService.qml (fallback-policy singleton, unrelated).
//
// Adaptation: upstream's `attemptCapture()` waits on a `shellQuiet` binding
// set from shell.qml (true once the bar/island has visually settled) before
// grabbing the frame, with a 900ms give-up timer. That binding does not
// exist in this shell (no single "shellQuiet" signal is wired from
// island/Island.qml or panels/*), so this file always waits a fixed
// `settleFrame` (32ms, same value) before capturing -- a documented
// simplification, not a silent drop: the risk is a screenshot that still
// shows the island/panel the lock was triggered from on the rare screen
// where one was open at that exact moment. Everything else (grim to a
// tmpfs runtime path, delete-on-forget, lock-anyway-if-capture-fails) is
// verbatim.
//
// Instantiated once by lock/LockScreen.qml (shared across every screen's
// surface, same object) and driven by LockScreen.lock()/unlock() so the
// capture happens BEFORE WlSessionLock.locked flips true -- once locked,
// the compositor blanks every output until the lock surface commits a
// buffer, so a screenshot taken after that point would capture black.
QtObject {
    id: root

    readonly property string shotDirectory:
        `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/quickshell`
    readonly property string shotPath: `${root.shotDirectory}/qml-rice-lock.png`

    // Bumped per capture so the Image source changes and Qt does not serve
    // the previous lock's cached frame.
    property int shotSerial: 0
    property bool shotReady: false

    readonly property string shotSource:
        root.shotReady ? `file://${root.shotPath}?v=${root.shotSerial}` : ""

    // Callback stashed across the settle timer/process round trip -- plain
    // JS var (fine on a QtObject; the "no var properties" rule in the hard
    // rules is IpcHandler-specific and does not apply here).
    property var _onDone: null

    function capture(onDone): void {
        root._onDone = onDone
        root.shotReady = false
        root.settleFrame.restart()
    }

    // grim reads the compositor, not this scene graph, and there is no
    // signal for "the frame is on screen" -- two frames at 60Hz, same as
    // upstream.
    readonly property Timer settleFrame: Timer {
        interval: 32
        onTriggered: root._beginCapture()
    }

    function _beginCapture(): void {
        root.capture_.running = true
    }

    // grim hangs instead of failing when the output is already powered
    // off, so this is wrapped in `timeout` the same as upstream. Named
    // `capture_` (trailing underscore) because `capture` above is already
    // the public function name.
    readonly property Process capture_: Process {
        command: ["sh", "-c",
            `mkdir -p '${root.shotDirectory}' && timeout 2 grim '${root.shotPath}'`]

        onExited: (code, status) => {
            root.shotSerial += 1
            root.shotReady = code === 0
            const done = root._onDone
            root._onDone = null
            // Lock whether or not the screenshot worked -- an untidy or
            // missing screenshot is better than an unlocked machine.
            if (done)
                done()
        }
    }

    function forget(): void {
        root.shotReady = false
        root.eraser.running = true
    }

    readonly property Process eraser: Process {
        command: ["rm", "-f", root.shotPath]
    }
}
