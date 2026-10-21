// Offscreen render harness for the dock. FloatingWindow + grabToImage(): no
// layer surface, no screen capture, no live input. The "pointer" is a
// synthetic x injected into DockSurface (syntheticX/Inside) -- the real mouse
// is never read. Writes PNGs for review to $DOCK_RENDER_OUT (default
// /tmp/dock-render):
//   sweep-00..08.png   pointer swept left -> right across the dock
//   rest.png           no pointer
//   bounce-*.png       launch bounce, 3 phases
//   menu.png           context menu on an icon
//   hidden.png / half.png  autohide slide states
//
// Run:  QT_QPA_PLATFORM=offscreen qs -p ./render-dock.qml
import QtQuick
import Quickshell
import "core"
import "dock"

FloatingWindow {
    id: window
    title: "dock render harness"
    implicitWidth: 1100
    implicitHeight: 360
    color: "#20243a"

    readonly property string outDir: Quickshell.env("DOCK_RENDER_OUT") || "/tmp/dock-render"
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
    }

    function shot(name) {
        root.grabToImage(function (result) {
            const ok = result.saveToFile(window.outDir + "/" + name + ".png")
            console.log("DOCKRENDER " + (ok ? "wrote " : "FAILED ") + name + ".png")
        })
    }

    function itemX(i) { return surface.rest.centers[surface.posOf[i]] }

    readonly property var script: {
        const s = []
        s.push({ t: 700, run: () => { surface.syntheticInside = false; surface.slide = 1; shot("rest") } })
        for (let k = 0; k < 9; k++) {
            const idx = k
            s.push({ t: 100, run: () => { surface.syntheticX = itemX(Math.min(idx, 8)) + (idx === 8 ? 0 : 0)
                surface.syntheticInside = true } })
            s.push({ t: 700, run: () => shot("sweep-0" + idx) })
        }
        // between two icons
        s.push({ t: 100, run: () => { surface.syntheticX = (itemX(2) + itemX(3)) / 2 } })
        s.push({ t: 700, run: () => shot("sweep-between") })
        s.push({ t: 100, run: () => { surface.syntheticX = itemX(0) } })
        s.push({ t: 700, run: () => { surface.openMenu(0); surface.syntheticInside = false } })
        s.push({ t: 400, run: () => shot("menu") })
        s.push({ t: 100, run: () => { surface.closeMenu() } })
        s.push({ t: 800, run: () => shot("bounce-a") })
        s.push({ t: 130, run: () => shot("bounce-b") })
        s.push({ t: 130, run: () => shot("bounce-c") })
        s.push({ t: 100, run: () => { surface.slide = 0.5 } })
        s.push({ t: 50, run: () => shot("half") })
        s.push({ t: 100, run: () => { surface.slide = 0 } })
        s.push({ t: 100, run: () => shot("hidden") })
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
