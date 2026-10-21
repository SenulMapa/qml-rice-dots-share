import QtQuick
import Quickshell
import Quickshell.Io
import "../core"
import "QuickLookFormat.js" as QL

/**
 * MacQuickLook -- macOS Quick Look (Space) for a file, mac style.
 *
 * Driven by `qml-rice ipc quicklook toggle <abs path>` (tools/quicklook/quicklook,
 * which Thunar's "Quick Look" action runs). MacStyleRoot routes
 * ShellActions.quickLookRequested here. Space or Esc closes; Left/Right/Up/Down
 * step through the other files of the same folder.
 *
 * Preview by kind (QuickLookFormat.kindOf): image and video and audio play in
 * QtMultimedia; text reads the first 200 lines; PDF renders page 1 with
 * pdftoppm into a temp PNG; everything else shows a big icon with metadata.
 *
 * Layer: `qml-rice:mac-quicklook` (blurred by the compositor glass rule family).
 * The window is built only with layer shell (MacTokens.layerShell), so the
 * offscreen harness never compiles it; the content is MacQuickLookPanel.
 */
Scope {
    id: root

    // Set while the preview is wanted on screen.
    property bool open: false
    // The window is built while open and through the fade-out.
    property bool mapped: false
    // Absolute path being previewed.
    property string path: ""
    // Sorted visible names in the folder of `path` (for arrow navigation).
    property var siblings: []
    // Result of `stat`: { bytes, modifiedMs, isDirectory } or null while loading.
    property var info: null
    // First lines of a text file ("" until read; null when binary).
    property string textPreview: ""
    // Path of the rendered PDF page 1 PNG, or "" until it exists.
    property string pdfPng: ""
    // Set when pdftoppm could not render (not installed, or a broken PDF).
    property string pdfError: ""

    readonly property string name: QL.nameOf(path)
    readonly property string dir: QL.dirOf(path)
    readonly property string kind: path === "" ? "other" : QL.kindOf(name)

    // Entry point for the IPC. action is "toggle", "show" or "close".
    function request(action: string, requested: string): void {
        let verb = action
        if (action === "toggle")
            verb = QL.toggleAction(root.path, requested, root.open)
        if (verb === "close") {
            close()
        } else if (verb === "show" && requested !== "") {
            show(requested)
        }
    }

    function show(target: string): void {
        const changed = target !== root.path
        root.path = target
        root.open = true
        hideTimer.stop()
        root.mapped = true
        if (changed || root.info === null)
            reload()
    }

    function close(): void {
        root.open = false
        hideTimer.restart()
    }

    // Move to the neighbouring file in the same folder (delta -1 or +1).
    function step(delta: int): void {
        const next = QL.neighbour(root.siblings, root.name, delta)
        if (next === "" || next === root.name)
            return
        show((root.dir === "/" ? "" : root.dir) + "/" + next)
    }

    function reload(): void {
        root.info = null
        root.textPreview = ""
        root.textBinary = false
        root.pdfError = ""
        root.removePdf()
        restart(statProc, ["stat", "-L", "-c", "%s %Y %F", "--", root.path])
        restart(listProc, ["find", root.dir, "-mindepth", "1", "-maxdepth", "1", "-printf", "%f\\n"])
        if (root.kind === "text")
            restart(textProc, ["head", "-c", "65536", "--", root.path])
        else if (root.kind === "pdf")
            restart(pdfProc, ["pdftoppm", "-png", "-r", "110", "-f", "1", "-l", "1", "-singlefile",
                root.path, root.pdfBase()])
    }

    function pdfBase(): string {
        return (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qml-rice-quicklook-" + Date.now()
    }

    function removePdf(): void {
        if (root.pdfPng !== "") {
            Quickshell.execDetached(["rm", "-f", root.pdfPng])
            root.pdfPng = ""
        }
    }

    // Each Process remembers the path it was started for. Results for any
    // other path are dropped, so a slow job for the previous file cannot
    // overwrite the current one.
    function restart(proc: var, cmd: var): void {
        proc.running = false
        proc.requested = root.path
        proc.command = cmd
        proc.running = true
    }

    function isCurrent(proc: var): bool {
        return proc.requested === root.path
    }

    Timer {
        id: hideTimer
        interval: 200
        onTriggered: {
            if (!root.open) {
                root.mapped = false
                root.removePdf()
            }
        }
    }

    Process {
        id: statProc
        property string requested: ""
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.isCurrent(statProc))
                    root.info = QL.parseStat(text) ?? { bytes: 0, modifiedMs: 0, isDirectory: false, failed: true }
            }
        }
        onExited: code => {
            if (code !== 0 && root.isCurrent(statProc))
                root.info = { bytes: 0, modifiedMs: 0, isDirectory: false, failed: true }
        }
    }

    Process {
        id: listProc
        property string requested: ""
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.isCurrent(listProc))
                    root.siblings = QL.sortNames((text || "").split("\n"))
            }
        }
    }

    Process {
        id: textProc
        property string requested: ""
        stdout: StdioCollector {
            onStreamFinished: {
                if (!root.isCurrent(textProc))
                    return
                const lines = QL.previewLines(text, 200)
                root.textBinary = lines === null
                root.textPreview = lines ?? ""
            }
        }
    }

    Process {
        id: pdfProc
        property string requested: ""
        stdout: StdioCollector { }
        onExited: code => {
            if (!root.isCurrent(pdfProc))
                return
            // The command's last argument is the output base; pdftoppm adds ".png".
            const base = pdfProc.command[pdfProc.command.length - 1]
            if (code === 0)
                root.pdfPng = base + ".png"
            else
                root.pdfError = "Could not render page 1 (needs pdftoppm from poppler)."
        }
    }

    // Set by textProc: the file was binary, so there is no text preview.
    property bool textBinary: false

    // The window is built only with layer shell (see MacTokens.layerShell).
    Loader {
        id: winLoader
        active: MacTokens.layerShell && root.mapped
        onActiveChanged: if (active) setSource("MacQuickLookWindow.qml",
            { screen: MacScreen.choose() })
        onLoaded: item.owner = root
    }
}
