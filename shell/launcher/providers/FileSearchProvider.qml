pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "search.js" as Search

// Filename search under $HOME for the palette. fd when it is installed,
// plocate otherwise. The search runs in a Process, never on the UI thread.
// A 150 ms debounce stops every keystroke from spawning a search, and a new
// query kills the run still going for the old one.
QtObject {
    id: root

    readonly property string providerId: "files"
    readonly property string displayName: "Files"
    readonly property int maxResults: 8
    // Bumped when results land, so the palette re-runs its query.
    property int revision: 0

    property var entries: []
    // The query the current entries belong to. query() drops them on any
    // other text, so a stale list never shows while the next search runs.
    property string entriesQuery: ""
    property string requestedQuery: ""
    property string runQuery: ""
    property int runCounter: 0
    property int activeRun: 0

    // The run id is echoed back as the first output line, so output from a
    // killed run cannot be mistaken for the current one.
    readonly property string script: "query=$1; run=$2\n"
        + "printf '%s\\n' \"$run\"\n"
        + "if command -v fd >/dev/null 2>&1; then\n"
        + "  fd --fixed-strings --ignore-case --max-results " + maxResults
        + " --exclude node_modules --exclude .cache -- \"$query\" \"$HOME\"\n"
        + "elif command -v plocate >/dev/null 2>&1; then\n"
        + "  plocate --ignore-case --basename --limit 500 -- \"$query\" 2>/dev/null |\n"
        + "    awk -v h=\"$HOME/\" 'index($0, h) == 1 {\n"
        + "      rel = substr($0, length(h) + 1)\n"
        + "      if (rel ~ /(^|\\/)\\./ || rel ~ /(^|\\/)node_modules(\\/|$)/) next\n"
        + "      print\n"
        + "    }' | head -n " + maxResults + "\n"
        + "fi\n"

    // QtObject takes no children, so the Timer and Process are declared as
    // properties, the same way CommandLauncherService declares its Process.
    property Timer debounce: Timer {
        interval: 150
        repeat: false
        onTriggered: root.startSearch()
    }

    property Process searchProcess: Process {
        stdout: StdioCollector {
            onStreamFinished: root.receive(text)
        }
    }

    // Called from the palette's search on every keystroke. Restarting the
    // debounce only when the text changed keeps the timer quiet while the
    // palette re-renders for other reasons.
    function query(queryText: string, limit: int): var {
        const needle = queryText.trim()
        if (needle !== root.requestedQuery) {
            root.requestedQuery = needle
            debounce.restart()
        }
        if (needle.length < Search.MIN_FILE_QUERY || needle !== root.entriesQuery)
            return []
        return root.entries.slice(0, limit).map((path, index) => fileResult(path, index))
    }

    function fileResult(path: string, index: int): var {
        const slash = path.lastIndexOf("/")
        const home = Quickshell.env("HOME")
        const folder = slash > 0 ? path.slice(0, slash) : "/"
        return {
            key: "file:" + path,
            provider: providerId,
            group: displayName,
            kind: "file",
            actionId: "open-file",
            title: path.slice(slash + 1),
            subtitle: home && folder.indexOf(home) === 0
                ? "~" + folder.slice(home.length) : folder,
            icon: "󰈔",
            iconKind: "glyph",
            badge: "File",
            score: 700 - index,
            path: path,
            enabled: true
        }
    }

    function startSearch(): void {
        if (searchProcess.running) {
            searchProcess.running = false
            // The kill may not have landed yet. Try again once it has.
            if (searchProcess.running) {
                debounce.restart()
                return
            }
        }
        const query = root.requestedQuery
        root.runCounter += 1
        root.activeRun = root.runCounter
        if (query.length < Search.MIN_FILE_QUERY) {
            root.entries = []
            root.entriesQuery = ""
            root.revision += 1
            return
        }
        root.runQuery = query
        searchProcess.command = ["sh", "-c", root.script, "files-search",
            query, String(root.activeRun)]
        searchProcess.running = true
    }

    function receive(output: string): void {
        const lines = output.split("\n")
        // A stale run prints an old id. Ignore it.
        if (Number(lines[0]) !== root.activeRun)
            return
        // fd writes directories with a trailing slash; the title needs the name.
        root.entries = lines.slice(1)
            .map(line => line.replace(/\/+$/, ""))
            .filter(line => line.length > 0)
        root.entriesQuery = root.runQuery
        root.revision += 1
    }

    function execute(result): var {
        if (!result?.path)
            return { handled: false }
        Quickshell.execDetached(["xdg-open", result.path])
        return { handled: true, dismiss: true }
    }
}
