// Offscreen render harness for the iPhone continuity UI. FloatingWindow +
// grabToImage(): no layer surface, no screen capture, no live input, no phonectl.
// Writes PNGs to $PHONE_RENDER_OUT (default /tmp/phone-render).
//
// Run:  QT_QPA_PLATFORM=offscreen qs -p ./render-phone.qml
import QtQuick
import Quickshell
import "core"
import "island"
import "components"

FloatingWindow {
    id: window
    title: "phone render harness"
    implicitWidth: 860
    implicitHeight: 560
    color: "#20243a"

    readonly property string outDir: Quickshell.env("PHONE_RENDER_OUT") || "/tmp/phone-render"
    property int step: 0

    QtObject {
        id: stub
        property var call: ({ id: "c1", state: "incoming", number: "+44 7700 900123", name: "Ada Lovelace", muted: false })
        function answer() {} function decline() {} function hangup() {}
        function setMuted(on) {}
        function reply(t, x, cb) { cb({ ok: false, error: "iPhone not connected" }) }
    }
    readonly property real t0: 1700000000000
    QtObject {
        id: msgStub
        property bool connected: true
        property var status: ({ v: 1, type: "status", connected: true, device: { name: "My iPhone", address: "AA" },
            battery: 82, charging: true, signal: 3, network: "5G", hotspot: { available: true, active: false },
            lockOnLeave: true, backend: "mock", trustedNetwork: true, error: null })
        function threads(cb) {
            cb({ ok: true, threads: [
                { id: "t1", name: "Ada Lovelace", participants: ["+44"], last: { text: "Table booked for two.", ts: window.t0 - 120000, outgoing: false }, unread: 2 },
                { id: "g1", name: "Lunch crew", participants: ["a", "b", "c"], last: { text: "Charles: see you there \ud83d\ude04", ts: window.t0 - 3 * 3600000, outgoing: false }, unread: 0 }
            ] })
        }
        function thread(id, cb) {
            cb({ ok: true, messages: [
                { id: "1", threadId: "t1", from: { name: "Ada Lovelace" }, text: "Are we still on for lunch at one?", ts: window.t0 - 3600000 * 2, outgoing: false },
                { id: "2", threadId: "t1", from: { name: "Me" }, text: "Yes! Where are we going?", ts: window.t0 - 3600000 * 2 + 60000, outgoing: true },
                { id: "3", threadId: "t1", from: { name: "Ada Lovelace" }, text: "The place by the canal. I booked the table by the window, and they said they can hold it until quarter past if you are running late, but not a minute longer than that.", ts: window.t0 - 3600000 * 2 + 120000, outgoing: false },
                { id: "4", threadId: "t1", from: { name: "Me" }, text: "Perfect.", ts: window.t0 - 3600000 * 2 + 180000, outgoing: true },
                { id: "5", threadId: "t1", from: { name: "Ada Lovelace" }, text: "Also: bring the notebook", ts: window.t0 - 600000, outgoing: false },
                { id: "6", threadId: "t1", from: { name: "Ada Lovelace" }, text: "Table booked for two.", ts: window.t0 - 120000, outgoing: false },
                { id: "7", threadId: "t1", from: { name: "Me" }, text: "On my way", ts: window.t0 - 60000, outgoing: true },
                { id: "8", threadId: "t1", from: { name: "Ada Lovelace" }, text: "\ud83d\udc4d", ts: window.t0 - 30000, outgoing: false }
            ] })
        }
        function reply(t, x, cb) { cb({ ok: true }) }
        function setHotspot(on) {} function setLockOnLeave(on) {}
    }
    QtObject {
        id: r2Stub
        property bool connected: true
        property var status: msgStub.status
        property string airplayState: "pin"
        property string airplayPin: ""
        property string airplayDevice: "Ada's iPhone"
        property bool cameraActive: false
        function airplayPassword(cb) { cb({ ok: true, password: "fixture-airplay-pw-not-real" }) }
        function cameraLink(cb) {
            cb({ ok: true, url: "larix://set/v1?conn[][url]=srt%3A%2F%2F192.168.1.20%3A7857%3Fpbkeylen%3D32&conn[][passphrase]=k3j4h5g6f7d8s9a0qwerty&conn[][name]=iphone-camera&videoConfig[][res]=1280x720" })
        }
        function setHotspot(on) {} function setLockOnLeave(on) {}
    }
    QtObject {
        id: offStub
        property bool connected: false
        property var status: ({ v: 1, type: "status", connected: false, device: null, battery: null, signal: null,
            hotspot: { available: false, active: false }, lockOnLeave: false, error: "phone-glue not running" })
        function setHotspot(on) {} function setLockOnLeave(on) {}
    }
    QtObject {
        id: ctl
        property string visualState: "phoneMessage"
        readonly property string phoneMessage: "phoneMessage"
        function clearTransient() {}
    }

    Rectangle {
        id: stage
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: "#3a2f6b" }
            GradientStop { position: 1; color: "#12182e" }
        }

        // The ink island body: black, large radius.
        Rectangle {
            id: body
            anchors.horizontalCenter: parent.horizontalCenter
            y: 24
            color: "#000000"
            radius: height / 2 > 34 ? 34 : height / 2
            width: 520; height: 104
            clip: true

            PhoneCallCard { id: card; anchors.fill: parent; service: stub; visible: false }
            PhoneCallPill { id: pill; anchors.fill: parent; service: stub; visible: false
                nowOverride: 1000000 + 83000 }
            MessagesPage { id: msgPage; anchors.fill: parent; service: msgStub; visible: false; nowOverride: window.t0 }
            PhoneSatelliteContent { id: satOn; anchors.fill: parent; service: msgStub; visible: false; lockOnLeaveValue: true }
            PhoneSatelliteContent { id: satOff; anchors.fill: parent; service: offStub; visible: false }
            PhoneAirplayPin { id: pinView; anchors.fill: parent; service: r2Stub; visible: false }
            PhoneLivePill { id: liveView; anchors.fill: parent; service: r2Stub; visible: false }
            PhoneSatelliteContent { id: satR2; anchors.fill: parent; service: r2Stub; visible: false }
            PhoneMessageToast {
                id: toast
                anchors.fill: parent
                visible: false
                service: stub
                controller: ctl
                showing: false
                timeoutMs: 600000
                entry: ({ id: "m1", threadId: "t1", from: { name: "Ada Lovelace", number: "+44 7700 900123" },
                    text: "Are we still on for lunch at one? I booked the table by the window, and they said they can hold it until quarter past if you are running late.",
                    ts: 1 })
            }
        }
    }

    function shot(name) {
        stage.grabToImage(function (result) {
            const ok = result.saveToFile(window.outDir + "/" + name + ".png")
            console.log("PHONERENDER " + (ok ? "wrote " : "FAILED ") + name + ".png")
        })
    }

    readonly property var script: [
        { t: 500, run: () => { body.width = 520; body.height = 104; card.visible = true } },
        { t: 500, run: () => shot("call-incoming") },
        { t: 300, run: () => { card.visible = false; body.width = 250; body.height = 44; pill.expanded = false; pill.visible = true } },
        { t: 500, run: () => shot("call-ringing-pill") },
        { t: 300, run: () => { pill.visible = false; stub.call = { id: "c1", state: "active", startedAt: 1000000, name: "Ada Lovelace", muted: false }
            body.width = 190; body.height = 44; pill.expanded = false; pill.visible = true } },
        { t: 500, run: () => shot("call-active") },
        { t: 300, run: () => { body.width = 340; body.height = 76; pill.expanded = true } },
        { t: 500, run: () => shot("call-active-expanded") },
        { t: 300, run: () => { pill.visible = false; body.width = 520; body.height = 132; toast.visible = true; toast.showing = true } },
        { t: 700, run: () => shot("message-toast") },
        { t: 300, run: () => { toast.replyText = "On my way!"; toast.sendReply() } },
        { t: 400, run: () => shot("message-toast-error") },
        { t: 300, run: () => { toast.visible = false; toast.showing = false; body.width = 780; body.height = 500; body.radius = 34; msgPage.visible = true } },
        { t: 900, run: () => shot("messages-page") },
        { t: 300, run: () => { msgPage.visible = false; body.width = 300; body.height = 250; satOn.visible = true } },
        { t: 600, run: () => shot("phone-satellite") },
        { t: 300, run: () => { satOn.visible = false; satOff.visible = true } },
        { t: 600, run: () => shot("phone-satellite-off") },
        { t: 300, run: () => { satOff.visible = false; body.width = 420; body.height = 104; body.radius = 34; pinView.visible = true } },
        { t: 500, run: () => shot("airplay-pin") },
        { t: 300, run: () => { pinView.visible = false; r2Stub.airplayState = "mirroring"; r2Stub.airplayPin = ""; r2Stub.cameraActive = true
            body.width = 210; body.height = 44; liveView.kind = "mirroring"; liveView.visible = true } },
        { t: 500, run: () => shot("mirroring") },
        { t: 300, run: () => { r2Stub.airplayState = "idle"; liveView.kind = "camera" } },
        { t: 500, run: () => shot("camera-live") },
        { t: 300, run: () => { liveView.visible = false; r2Stub.airplayState = "mirroring"; body.width = 300; satR2.visible = true; body.height = satR2.contentHeight } },
        { t: 600, run: () => shot("phone-satellite-r2") },
        { t: 300, run: () => { satR2.toggleAirplayPassword(); Qt.callLater(() => body.height = satR2.contentHeight) } },
        { t: 600, run: () => shot("phone-satellite-password") },
        { t: 300, run: () => { satR2.clearReveal(); Qt.callLater(() => body.height = satR2.contentHeight) } },
        { t: 300, run: () => satR2.openCameraSetup() },
        { t: 700, run: () => shot("phone-satellite-r2-qr") },
        { t: 500, run: () => Qt.quit() }
    ]

    Timer {
        id: runner
        repeat: false
        onTriggered: {
            window.script[window.step].run()
            window.step++
            if (window.step < window.script.length) {
                runner.interval = window.script[window.step].t
                runner.start()
            }
        }
    }
    Component.onCompleted: {
        Quickshell.execDetached(["mkdir", "-p", window.outDir])
        runner.interval = window.script[0].t
        runner.start()
    }
}
