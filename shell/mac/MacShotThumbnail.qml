import QtQuick
import Quickshell
import Quickshell.Io
import "../core"
import "../components"

/**
 * MacShotThumbnail -- the floating screenshot thumbnail (macOS Cmd+Shift+3/4/5).
 *
 * Captures come from tools/mac-screenshot/shot, which appends one JSON line
 * per capture to queuePath: {"id","path","mode"}. This item watches that file,
 * shows each new capture for MacTokens.shotLifetimeMs, and then moves on to
 * the next queued one. Hovering pauses the countdown.
 *
 *   click        open in the annotator (satty, else swappy, else xdg-open)
 *   drag         drag source for the PNG as text/uri-list
 *   X            discard: moves the file to the trash (gio trash)
 *
 * Built only with layer shell (see MacShotWindow.qml and MacTokens.layerShell).
 * The queue logic (ingest, enqueue, advance, tick) is plain functions so
 * test-mac-shot.qml can drive it offscreen with autoTick false.
 */
Item {
    id: root

    // Same file the script writes, in the per-user runtime dir. No /tmp
    // fallback: with XDG_RUNTIME_DIR unset the feature is off (queuePath "").
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
    property string queuePath: runtimeDir !== "" ? runtimeDir + "/qml-rice/mac-shot.jsonl" : ""
    // Captures must live here (the script's ~/Pictures/Screenshots). Anything
    // else in the queue file is refused.
    readonly property string screenshotDir: Quickshell.env("HOME")
        ? Quickshell.env("HOME") + "/Pictures/Screenshots/" : ""
    // Trust gate for every path that reaches gio trash, xdg-open or Image.
    function safePath(path: var): bool {
        if (typeof path !== "string" || screenshotDir === "")
            return false
        if (path.indexOf("/") !== 0)            // absolute only: no relative, no file:// URI
            return false
        if (path.indexOf("..") >= 0)            // no traversal
            return false
        if (path.slice(-4) !== ".png")          // PNG only
            return false
        return path.indexOf(screenshotDir) === 0 // inside the screenshot folder
    }
    // Number of external processes started (trash or open). Lets tests check
    // that a rejected path never reaches a process.
    property int spawnCount: 0
    // The test harness turns this off and calls tick() itself.
    property bool autoTick: true

    readonly property int lifetimeMs: MacTokens.shotLifetimeMs
    readonly property int maxPending: MacTokens.shotMaxPending

    // ---- queue state ---------------------------------------------------
    // current: the capture on screen, {id, path, mode}, or null.
    // pending: FIFO of captures waiting their turn.
    property var current: null
    property var pending: []
    property int remainingMs: 0
    property bool hovered: false
    readonly property bool busy: current !== null
    // Ids already seen, oldest first. Capped so a long session cannot grow it.
    property var seenIds: []
    readonly property int seenCap: 200
    property bool primed: false

    // Parses JSONL text. `announce` false only for the first read after the
    // shell starts: existing history is marked seen and never shown.
    // Returns how many captures were queued.
    function ingest(text: string, announce: bool): int {
        const lines = String(text).split("\n")
        let added = 0
        for (const raw of lines) {
            const line = raw.trim()
            if (line === "")
                continue
            let entry = null
            try {
                entry = JSON.parse(line)
            } catch (e) {
                continue
            }
            if (!entry || typeof entry.id !== "string")
                continue
            if (isSeen(entry.id))
                continue
            markSeen(entry.id)
            if (!safePath(entry.path))
                continue
            if (announce && enqueue(entry))
                added++
        }
        return added
    }

    function isSeen(id: string): bool {
        return seenIds.indexOf(id) >= 0
    }

    function markSeen(id: string): void {
        const ids = seenIds.concat([id])
        seenIds = ids.length > seenCap ? ids.slice(ids.length - seenCap) : ids
    }

    // Shows the entry now when nothing is on screen, otherwise queues it.
    // The oldest pending entry is dropped when the queue is full; its file
    // stays on disk, only its thumbnail is skipped.
    function enqueue(entry: var): bool {
        if (current === null) {
            current = entry
            remainingMs = lifetimeMs
            return true
        }
        let queue = pending.concat([entry])
        while (queue.length > maxPending)
            queue = queue.slice(1)
        pending = queue
        return true
    }

    // Moves to the next pending capture, or clears the card.
    function advance(): void {
        if (pending.length > 0) {
            const queue = pending.slice()
            current = queue.shift()
            pending = queue
        } else {
            current = null
        }
        remainingMs = lifetimeMs
    }

    // Counts the on-screen capture down. Hovering freezes it.
    function tick(ms: int): void {
        if (current === null || hovered)
            return
        remainingMs -= ms
        if (remainingMs <= 0)
            advance()
    }

    // Both re-check the path: the entry was vetted at ingest, but nothing
    // external may act on a path that fails the gate. A rejected capture is
    // skipped and nothing is spawned.
    function discard(): void {
        if (current === null)
            return
        if (safePath(current.path)) {
            trasher.command = ["gio", "trash", "--", current.path]   // argv, never a shell string
            trasher.running = true
            spawnCount++
        } else {
            console.warn("qml-rice MacShotThumbnail: refused to trash a path outside the screenshot dir")
        }
        advance()
    }

    function openCurrent(): void {
        if (current === null)
            return
        if (safePath(current.path)) {
            // "$1" is the path, passed as an argv element after the script string.
            opener.command = ["sh", "-c",
                "if command -v satty >/dev/null 2>&1; then exec satty --filename \"$1\"; "
                + "elif command -v swappy >/dev/null 2>&1; then exec swappy -f \"$1\"; "
                + "else exec xdg-open \"$1\"; fi",
                "sh", current.path]
            opener.running = true
            spawnCount++
        } else {
            console.warn("qml-rice MacShotThumbnail: refused to open a path outside the screenshot dir")
        }
        advance()
    }

    function fileUri(path: string): string {
        return "file://" + encodeURI(path).replace(/#/g, "%23").replace(/\?/g, "%3F")
    }

    Timer {
        interval: MacTokens.bannerTimeoutTick
        running: root.autoTick && root.current !== null && !root.hovered
        repeat: true
        onTriggered: root.tick(interval)
    }

    FileView {
        id: queueFile
        path: root.queuePath
        watchChanges: true
        blockLoading: false
        printErrors: false
        onLoaded: {
            root.ingest(text(), root.primed)
            root.primed = true
        }
        onLoadFailed: error => {
            // No file yet means no capture has happened: nothing to announce.
            root.primed = true
        }
        onFileChanged: reload()
    }

    Process {
        id: trasher
        onExited: code => {
            if (code !== 0)
                console.warn("qml-rice MacShotThumbnail: gio trash failed with", code)
        }
    }

    Process {
        id: opener
        onExited: code => {
            if (code !== 0)
                console.warn("qml-rice MacShotThumbnail: opener failed with", code)
        }
    }

    // ---- card ----------------------------------------------------------
    readonly property real pad: MacTokens.s(MacTokens.shotInset)
    implicitWidth: MacTokens.s(MacTokens.shotWidth)
    // Height follows the picture. thumb never reads root.height, so no loop.
    implicitHeight: thumb.height + 2 * pad
    width: implicitWidth
    height: implicitHeight
    visible: current !== null

    // Fades in each time a new capture takes the card.
    property real shownOpacity: 1
    onCurrentChanged: {
        if (current !== null) {
            shownOpacity = 0
            fadeIn.restart()
        }
    }
    NumberAnimation {
        id: fadeIn
        target: root
        property: "shownOpacity"
        to: 1
        duration: MacTokens.shotFadeMs
        easing.type: Easing.OutCubic
    }

    Squircle {
        id: card
        anchors.fill: parent
        radius: MacTokens.s(MacTokens.shotRadius)
        color: Theme.ink
        borderWidth: 1
        borderColor: Theme.inkRim
        opacity: root.shownOpacity

        Image {
            id: thumb
            x: root.pad
            y: root.pad
            width: root.width - 2 * root.pad
            height: status === Image.Ready && sourceSize.width > 0
                ? width * sourceSize.height / sourceSize.width
                : width * 0.625
            source: root.current ? root.fileUri(root.current.path) : ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: false
            smooth: true
            mipmap: true
        }

        // Drag the PNG out to another app as a file URI.
        Item {
            id: dragSource
            anchors.fill: thumb
            Drag.active: dragger.active
            Drag.dragType: Drag.Automatic
            Drag.supportedActions: Qt.CopyAction
            Drag.hotSpot.x: width / 2
            Drag.hotSpot.y: height / 2
            Drag.mimeData: ({ "text/uri-list": root.current ? root.fileUri(root.current.path) : "" })
        }

        DragHandler {
            id: dragger
            target: null
            enabled: root.current !== null
        }

        TapHandler {
            enabled: root.current !== null
            onTapped: root.openCurrent()
        }

        HoverHandler {
            onHoveredChanged: root.hovered = hovered
        }

        // X: discard. Top-left, like the macOS close badge.
        Rectangle {
            id: closeBadge
            width: MacTokens.s(18)
            height: width
            radius: width / 2
            // Inside the card: the window mask only takes clicks on the card.
            x: MacTokens.s(6)
            y: MacTokens.s(6)
            color: Theme.ink
            border.width: 1
            border.color: Theme.inkRim
            visible: root.current !== null

            Text {
                anchors.centerIn: parent
                text: "×"
                color: MacTokens.labelPrimary
                font.family: MacTokens.textFamily
                font.pixelSize: MacTokens.s(12)
                font.weight: Font.DemiBold
            }
            TapHandler {
                onTapped: root.discard()
            }
        }
    }
}
