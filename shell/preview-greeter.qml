// Render harness for lock/GlassLockSurface.qml (the liquid-glass greeter).
//
//   GREETER_VIDEO=file:///path/to/loop.mp4 qs -p ./preview-greeter.qml
//
// A plain FloatingWindow -- never a WlSessionLock -- driven by
// FakePamAuthenticator, with `interactive: false` so nothing takes keyboard
// focus (unless PREVIEW_STAY=1), and fake connectivity numbers instead of the live services. It
// grabs two frames ~1.5s apart (to prove the video is moving) plus the
// StatusOrb at 8x in two states into /tmp/greeter-preview/, then quits.
// PREVIEW_STAY=1 keeps the window open afterwards.
import QtQuick
import Quickshell
import "lock"
import "components"

FloatingWindow {
    id: window
    title: "greeter preview"
    implicitWidth: 1920
    implicitHeight: 1080
    color: "black"

    readonly property string outDir: "/tmp/greeter-preview"
    readonly property bool stay: Quickshell.env("PREVIEW_STAY") === "1"

    FakePamAuthenticator { id: fakePam }
    LockContext { id: previewContext; authenticator: fakePam }

    QtObject {
        id: fakeLinks
        property real wifiStrength: 0.7
        property bool ethernet: false
        property bool btEnabled: true
        property real btSignal: 0.8
        property int btDevices: 2
    }

    // Fixed 1920x1080 regardless of how the compositor sizes the window
    // (Hyprland tiles it); grabToImage renders the item at its own size.
    GlassLockSurface {
        id: surface
        width: 1920
        height: 1080
        context: previewContext
        // Typeable only when a person asked for the window to stay; the
        // fake authenticator accepts "test", anything else shakes.
        interactive: window.stay
        connectivity: fakeLinks
        userName: Quickshell.env("GREETER_NAME") || Quickshell.env("USER") || "user"
        videoSource: Quickshell.env("GREETER_VIDEO") || ""
        avatarSource: Quickshell.env("GREETER_AVATAR") || ("file://" + Quickshell.env("HOME") + "/.face")
    }

    // Orb close-ups: hidden during the full-frame grabs.
    Row {
        id: orbs
        visible: false
        z: 10
        padding: 24
        spacing: 48
        Rectangle {
            width: 400; height: 400; radius: 40; color: "#1a0a2a"
            StatusOrb {
                anchors.centerIn: parent; width: 336; height: 336
                wifiStrength: 0.7; btEnabled: true; btSignal: 0.8; btDevices: 2
            }
        }
        Rectangle {
            width: 400; height: 400; radius: 40; color: "#1a0a2a"
            StatusOrb {
                anchors.centerIn: parent; width: 336; height: 336
                wifiStrength: 0.3; btEnabled: true; btSignal: 0.4; btDevices: 1
            }
        }
        Rectangle {
            width: 400; height: 400; radius: 40; color: "#1a0a2a"
            StatusOrb {
                anchors.centerIn: parent; width: 336; height: 336
                wifiStrength: -1; ethernet: true; btEnabled: false
            }
        }
    }

    // After the stills: "type" into the field and grab the password row at
    // a few lengths, mid-animation and settled.
    // [text length, ms to wait before grabbing]; 7..9 add one char at a time
    // to show a single new dot popping while the others stay put.
    property var typeShots: [[0, 300], [1, 60], [1, 400], [6, 400], [7, 70], [8, 400], [14, 130], [14, 500], [40, 500], [0, 120], [0, 600]]
    property int typeStep: 0
    Timer {
        id: typeTimer
        running: false
        interval: window.typeShots[window.typeStep][1]
        onTriggered: {
            const n = window.typeStep;
            surface.grabToImage(r => {
                r.saveToFile(`${window.outDir}/type-${n}.png`);
                if (n + 1 < window.typeShots.length) {
                    window.typeStep = n + 1;
                    surface.passwordText = "x".repeat(window.typeShots[n + 1][0]);
                    typeTimer.restart();
                } else {
                    tiltTimer.start();
                }
            });
        }
    }

    // Then the 3D clock: pin the pointer to two corners and grab each once
    // the tilt has settled, plus one idle-drift frame.
    property var tiltShots: [Qt.point(0, 0), Qt.point(900, 280), null]
    property int tiltStep: 0
    Timer {
        id: tiltTimer
        interval: 1400
        onTriggered: {
            const n = window.tiltStep;
            if (n > 0 || surface.clockPointer !== null || n === 0 && window.tiltShots[0] === null) {}
            surface.grabToImage(r => {
                if (n > 0) r.saveToFile(`${window.outDir}/tilt-${n - 1}.png`);
                if (n < window.tiltShots.length) {
                    surface.clockPointer = window.tiltShots[n];
                    window.tiltStep = n + 1;
                    tiltTimer.restart();
                } else if (!window.stay) {
                    Qt.quit();
                }
            });
        }
    }

    property int step: 0
    Timer {
        interval: window.step === 0 ? 3500 : 1500
        running: window.step < 4
        repeat: true
        onTriggered: {
            const n = window.step++;
            if (n === 0 || n === 1) {
                surface.grabToImage(r => r.saveToFile(`${window.outDir}/frame-${n + 1}.png`));
            } else if (n === 2) {
                orbs.visible = true;
            } else {
                orbs.grabToImage(r => {
                    r.saveToFile(`${window.outDir}/orb.png`);
                    orbs.visible = false;
                    surface.passwordText = "";
                    typeTimer.start();
                });
            }
        }
    }
}
