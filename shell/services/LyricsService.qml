pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../core"
import "."

/**
 * LyricsService - time-synced lyrics for the resting pill.
 *
 * Source: LRCLIB (free, no API key). Lookup is /api/get with title, artist and
 * duration; a 404 falls back to /api/search, whose results are ranked by
 * RELEVANCE, not length: searching "Blinding Lights" returns "Get Lucky" at
 * 248 s fourth. A search result is therefore only accepted when its title
 * matches AND its duration is within 2 s of the playing track, or the pill
 * would sync another song's words.
 *
 * Timing without extra wakeups. MediaService polls position once a second,
 * which alone would put lines up to a second late. Position is interpolated
 * from the last poll instead, and a single-shot timer sleeps until the next
 * line's timestamp. Nothing ticks between lines.
 *
 * Status: idle | loading | ready | missing | instrumental | error. Errors are
 * never cached (the network may come back); everything else is, per track.
 *
 * QMLRICE_TRACE_LYRICS=1 logs status, line changes and interpolated position.
 */
QtObject {
    id: root

    readonly property bool enabled: Config.media.lyricsEnabled
    readonly property bool trace: Quickshell.env("QMLRICE_TRACE_LYRICS") === "1"
    readonly property string userAgent: "qml-rice (https://github.com/SenulMapa)"
    readonly property string noteGlyph: String.fromCharCode(0x266A)
    readonly property var gapPattern: new RegExp(
        "^[" + String.fromCharCode(0x266A, 0x266B) + "\\s]*$")
    readonly property var titleNoise: new RegExp(
        "[^a-z0-9" + String.fromCharCode(0xC0) + "-" + String.fromCharCode(0xFFFF) + "]+", "g")

    property string status: "idle"
    property var lines: []
    property int index: -1
    // Per the design: only the meter and clock for the first moments of a
    // song, THEN the pill widens and the lyrics appear between them.
    property bool revealed: false

    // index >= 0: the band waits for the first SUNG line. Revealing on
    // schedule alone widened the pill to show a lone note glyph for the seconds
    // before a song's first lyric -- nothing to put between meter and clock.
    // Mid-song gaps still show the glyph, so the band never flaps.
    readonly property bool active: enabled && revealed && MediaService.playing
        && status === "ready" && lines.length > 0 && index >= 0
    readonly property string currentLine: index >= 0 && index < lines.length
        && lines[index].text.length > 0 ? lines[index].text : noteGlyph

    property string trackKey: ""
    property string trackTitle: ""
    property string trackArtist: ""
    property real trackDuration: 0

    property string requestKey: ""
    property string requestPhase: ""
    property string requestTitle: ""
    property real requestDuration: 0
    property var followUp: null
    property string pendingKey: ""
    property var cache: ({})
    property var cacheOrder: []

    property real anchorPosition: 0
    property real anchorTime: 0

    // ---- pure functions (covered by test-lyrics.qml) -------------------

    function parseLrc(text) {
        const out = []
        const lead = /^((?:\s*\[\d+:\d+(?:\.\d+)?\])+)(.*)$/
        const stamp = /\[(\d+):(\d+(?:\.\d+)?)\]/g
        for (const raw of String(text || "").split(/\r?\n/)) {
            const m = lead.exec(raw)
            if (!m)
                continue
            let body = m[2].trim()
            // A line of only note glyphs marks an instrumental gap.
            if (gapPattern.test(body))
                body = ""
            stamp.lastIndex = 0
            let s
            while ((s = stamp.exec(m[1])) !== null)
                out.push({ t: Number(s[1]) * 60 + Number(s[2]), text: body })
        }
        out.sort((a, b) => a.t - b.t)
        return out
    }

    function indexAt(ls, t) {
        if (!ls || ls.length === 0 || t < ls[0].t)
            return -1
        let lo = 0, hi = ls.length - 1
        while (lo < hi) {
            const mid = (lo + hi + 1) >> 1
            if (ls[mid].t <= t) lo = mid
            else hi = mid - 1
        }
        return lo
    }

    function normalizeTitle(s) {
        return String(s || "").toLowerCase()
            .replace(/[\(\[].*?[\)\]]/g, " ")
            .replace(/\s+-\s+.*$/, "")
            .replace(titleNoise, " ")
            .trim()
    }

    function titlesMatch(a, b) {
        const x = normalizeTitle(a), y = normalizeTitle(b)
        if (x.length === 0 || y.length === 0)
            return false
        return x === y || x.startsWith(y) || y.startsWith(x)
    }

    function pickSearchResult(results, title, duration) {
        if (!Array.isArray(results))
            return null
        for (const r of results) {
            if (!r || !r.syncedLyrics || r.instrumental)
                continue
            if (!titlesMatch(r.trackName || r.name, title))
                continue
            if (duration > 0 && Math.abs(Number(r.duration) - duration) > 2)
                continue
            return r
        }
        return null
    }

    function buildGetUrl(title, artist, duration) {
        return "https://lrclib.net/api/get?track_name=" + encodeURIComponent(title)
            + "&artist_name=" + encodeURIComponent(artist)
            + (duration > 0 ? "&duration=" + Math.round(duration) : "")
    }

    function buildSearchUrl(title, artist) {
        return "https://lrclib.net/api/search?track_name=" + encodeURIComponent(title)
            + "&artist_name=" + encodeURIComponent(artist)
    }

    function safeParse(body) {
        try { return JSON.parse(body) } catch (e) { return null }
    }

    // ---- timing ----------------------------------------------------------

    function estimatedPosition(): real {
        return MediaService.playing
            ? anchorPosition + (Date.now() - anchorTime) / 1000 : anchorPosition
    }

    function reschedule(): void {
        lineTimer.stop()
        if (status !== "ready" || lines.length === 0) {
            index = -1
            return
        }
        // Lead slightly so a line lands as it is sung, not after.
        const t = estimatedPosition() + Config.media.lyricsLeadMs / 1000
        const i = indexAt(lines, t)
        if (i !== index)
            index = i
        if (!MediaService.playing || i + 1 >= lines.length)
            return
        lineTimer.interval = Math.max(16, Math.round((lines[i + 1].t - t) * 1000) + 20)
        lineTimer.start()
    }

    // ---- track + fetch ---------------------------------------------------

    function refreshTrack(): void {
        const player = MediaService.activePlayer
        const title = player?.trackTitle || ""
        const artist = player?.trackArtist || ""
        const duration = MediaService.duration
        const key = title.length > 0
            ? JSON.stringify([artist, title, Math.round(duration)]) : ""
        if (key === trackKey)
            return
        trackKey = key
        trackTitle = title
        trackArtist = artist
        trackDuration = duration
        lineTimer.stop()
        index = -1
        lines = []
        revealed = false
        if (MediaService.playing) revealTimer.restart()
        else revealTimer.stop()
        if (!enabled || key.length === 0) {
            status = "idle"
            return
        }
        const hit = cache[key]
        if (hit) {
            apply(hit.status, hit.lines)
            return
        }
        status = "loading"
        request(key, "get")
    }

    function request(key, phase): void {
        if (lyricsRequest.running) {
            pendingKey = key
            return
        }
        startRequest(key, phase)
    }

    function startRequest(key, phase): void {
        requestKey = key
        requestPhase = phase
        requestTitle = trackTitle
        requestDuration = trackDuration
        const url = phase === "search"
            ? buildSearchUrl(trackTitle, trackArtist)
            : buildGetUrl(trackTitle, trackArtist, trackDuration)
        // --write-out instead of --fail: a 404 must stay distinguishable from a
        // network failure, because only the former means "try search".
        lyricsRequest.command = ["curl", "--silent", "--show-error",
            "--max-time", String(Config.media.lyricsRequestTimeout),
            "-A", userAgent, "--write-out", "\n%{http_code}", url]
        lyricsRequest.running = true
    }

    function handleResponse(text): void {
        const key = requestKey
        const cut = text.lastIndexOf("\n")
        const code = cut >= 0 ? text.slice(cut + 1).trim() : ""
        const body = cut >= 0 ? text.slice(0, cut) : text
        if (requestPhase === "get") {
            if (code === "200") acceptPayload(key, safeParse(body))
            else if (code === "404") followUp = { key: key, phase: "search" }
            else finish(key, "error", [])
        } else if (code === "200") {
            const pick = pickSearchResult(safeParse(body), requestTitle, requestDuration)
            if (pick) acceptPayload(key, pick)
            else finish(key, "missing", [])
        } else {
            finish(key, "error", [])
        }
        Qt.callLater(root.drainQueue)
    }

    function acceptPayload(key, p): void {
        if (!p) {
            finish(key, "error", [])
            return
        }
        if (p.instrumental) {
            finish(key, "instrumental", [])
            return
        }
        const parsed = parseLrc(p.syncedLyrics || "")
        finish(key, parsed.length > 0 ? "ready" : "missing", parsed)
    }

    function finish(key, st, ls): void {
        if (st !== "error")
            remember(key, st, ls)
        if (key === trackKey)
            apply(st, ls)
    }

    function apply(st, ls): void {
        lines = ls
        index = -1
        status = st
        reschedule()
    }

    function remember(key, st, ls): void {
        if (!cache[key])
            cacheOrder.push(key)
        cache[key] = { status: st, lines: ls }
        while (cacheOrder.length > 40)
            delete cache[cacheOrder.shift()]
    }

    // Order-independent: stdout's onStreamFinished and the Process's onExited
    // may arrive either way round, so both schedule this, and it acts only once
    // the process has actually stopped.
    function drainQueue(): void {
        if (lyricsRequest.running)
            return
        const next = followUp
        followUp = null
        if (next && next.key === trackKey) {
            startRequest(next.key, next.phase)
            return
        }
        if (pendingKey.length > 0) {
            const k = pendingKey
            pendingKey = ""
            if (k === trackKey)
                startRequest(k, "get")
        }
    }

    property Process lyricsRequest: Process {
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.handleResponse(text)
        }
        onExited: (exitCode, exitStatus) => Qt.callLater(root.drainQueue)
    }

    property Timer trackDebounce: Timer {
        // Players publish title, artist and length as separate updates;
        // without this one track change would fire three lookups.
        interval: 350
        onTriggered: root.refreshTrack()
    }

    property Timer revealTimer: Timer {
        interval: Config.media.lyricsRevealDelay
        onTriggered: root.revealed = true
    }

    property Timer lineTimer: Timer {
        onTriggered: root.reschedule()
    }

    property Connections mediaEvents: Connections {
        target: MediaService
        function onTitleChanged(): void { root.trackDebounce.restart() }
        function onArtistChanged(): void { root.trackDebounce.restart() }
        function onDurationChanged(): void { root.trackDebounce.restart() }
        function onPositionChanged(): void {
            root.anchorPosition = MediaService.position
            root.anchorTime = Date.now()
            root.reschedule()
        }
        function onPlayingChanged(): void {
            // Settle the anchor at the moment of change. On pause, the time
            // since the last poll WAS playback so it counts; on resume it was
            // not, so the clock restarts from the frozen position.
            if (!MediaService.playing)
                root.anchorPosition = root.anchorPosition + (Date.now() - root.anchorTime) / 1000
            root.anchorTime = Date.now()
            if (MediaService.playing) {
                if (!root.revealed) root.revealTimer.restart()
            } else {
                root.revealTimer.stop()
            }
            root.reschedule()
        }
    }

    onStatusChanged: if (trace) console.log("LYRICS status t=" + Date.now() + " status=" + status + " lines=" + lines.length)
    // Reads lines[index] directly, NOT currentLine: inside onIndexChanged the
    // currentLine binding has not re-evaluated yet, so it reports the PREVIOUS
    // line. That off-by-one once made an accurate +30 ms sync read as +2829 ms.
    onIndexChanged: if (trace) console.log("LYRICS line t=" + Date.now() + " index=" + index
        + " pos=" + estimatedPosition().toFixed(2) + " text="
        + (index >= 0 && index < lines.length ? (lines[index].text || noteGlyph) : noteGlyph))
    onActiveChanged: if (trace) console.log("LYRICS active t=" + Date.now() + " active=" + active + " revealed=" + revealed)

    Component.onCompleted: {
        anchorPosition = MediaService.position
        anchorTime = Date.now()
        trackDebounce.restart()
    }
}
