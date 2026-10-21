// Offscreen macOS-gloss render harness (dock, label, menu, notification). FloatingWindow + grabToImage(): no
// layer surface, no screen capture, no live input. The "pointer" is a
// synthetic x injected into DockSurface (syntheticX/Inside) -- the real mouse
// is never read. Writes PNGs for review to $GLOSS_RENDER_OUT (default
// /tmp/dock-render):
//   dock-rest, dock-magnified-label, menu, notification
//
// Run:  QT_QPA_PLATFORM=offscreen qs -p ./render-gloss.qml
import QtQuick
import Quickshell
import "core"
import "dock"
import "components"

FloatingWindow {
    id: window
    title: "gloss render harness"
    implicitWidth: 1100
    implicitHeight: 360
    color: "#20243a"

    readonly property string outDir: Quickshell.env("GLOSS_RENDER_OUT") || "/tmp/gloss-render"
    property var frames: []
    property int step: 0
    property var log: []

    function fake(key, name, icon, extra) {
        return Object.assign({ kind: "app", key: key, desktopId: key, name: name, icon: icon, "class": key,
            pinned: true, running: false, windowCount: 0, minimizedAddresses: [], addresses: [], windows: [],
            focused: false, launching: false, title: "" }, extra || {})
    }
    readonly property var sample: [
        fake("brave-browser", "Brave", "brave-browser", { running: true, windowCount: 2,
            addresses: ["0x1", "0x2"], windows: [{ address: "0x1", title: "Inbox - Mail" }, { address: "0x2", title: "Docs" }] }),
        fake("kitty", "kitty", "kitty", { running: true, windowCount: 1, addresses: ["0x3"], windows: [{ address: "0x3", title: "~" }] }),
        fake("code", "Code", "code", {}),
        fake("spotify", "Spotify", "spotify", { running: true, windowCount: 1, addresses: ["0x4"], windows: [{ address: "0x4", title: "Spotify" }] }),
        fake("discord", "Discord", "discord", {}),
        fake("slack", "Slack", "slack", { launching: true }),
        fake("thunar", "Thunar", "thunar", {}),
        { kind: "separator", key: "separator" },
        { kind: "minimized", key: "min:0x9", address: "0x9", name: "Notes", icon: "text-editor", appKey: "x", running: false, pinned: false, focused: false, launching: false }
    ]

    Rectangle {
        id: root
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: "#3a2f6b" }
            GradientStop { position: 1; color: "#12182e" }
        }

        DockSurface {
            id: surface
            anchors.fill: parent
            items: window.sample
            dockScale: 1.0
            synthetic: true
            animateAppear: false
        }

        // Stand-in for a notification (the real ones are painted by the island, which must not change).
        MacMaterial {
            id: notif
            visible: false
            x: parent.width - width - 24; y: 24
            width: 340; height: 76; radius: 14
            fill: Qt.rgba(0.16, 0.16, 0.17, 0.74)
            Text { x: 16; y: 14; text: "Messages"; font.family: "system-ui"; font.pixelSize: 12; font.weight: Font.DemiBold; color: Qt.rgba(1, 1, 1, 0.9) }
            Text { x: 16; y: 34; text: "Ada: lunch at one?"; font.family: "system-ui"; font.pixelSize: 13; color: Qt.rgba(1, 1, 1, 0.92) }
            Text { x: 16; y: 53; text: "Table booked for two."; font.family: "system-ui"; font.pixelSize: 12; color: Qt.rgba(1, 1, 1, 0.6) }
        }
    }

    function shot(name) {
        root.grabToImage(function (result) {
            const ok = result.saveToFile(window.outDir + "/" + name + ".png")
            console.log("GLOSSRENDER " + (ok ? "wrote " : "FAILED ") + name + ".png")
        })
    }

    function itemX(i) { return surface.rest.centers[surface.posOf[i]] }

    readonly property var script: {
        const s = []
        s.push({ t: 700, run: () => { surface.syntheticInside = false; surface.slide = 1; shot("dock-rest") } })
        s.push({ t: 100, run: () => { surface.syntheticX = itemX(1); surface.syntheticInside = true } })
        s.push({ t: 800, run: () => shot("dock-magnified-label") })
        s.push({ t: 100, run: () => { surface.syntheticX = itemX(0); surface.syntheticInside = true } })
        s.push({ t: 700, run: () => { surface.openMenu(0); surface.syntheticInside = false } })
        s.push({ t: 400, run: () => shot("menu") })
        s.push({ t: 100, run: () => { surface.closeMenu(); notif.visible = true } })
        s.push({ t: 400, run: () => shot("notification") })
        s.push({ t: 100, run: () => Qt.quit() })
        return s
    }

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
        runner.interval = 600
        runner.start()
        runner.interval = window.script[0].t
    }
}
