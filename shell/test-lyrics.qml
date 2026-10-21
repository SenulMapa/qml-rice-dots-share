// Offline tests for LyricsService's pure logic: LRC parsing, line lookup at a
// playback position, and -- the one that matters most -- rejecting a search
// result that is the wrong song with the right length.
import QtQuick
import Quickshell
import "services"
ShellRoot {
    id: root
    property var log: []
    function ok(name, cond, detail) {
        log.push((cond ? "PASS  " : "FAIL  ") + name + (detail ? "   " + detail : ""))
    }
    Timer {
        interval: 50; running: true
        onTriggered: {
            const L = LyricsService
            const lrc = "[ar:The Weeknd]\n[00:13.13] Yeah\n[00:16.56] ♪\n\n"
                + "[00:05.00][00:30.00] Chorus\n[01:02.5] Late line\nnot a lyric"
            const p = L.parseLrc(lrc)
            root.ok("parse_count", p.length === 5, "got " + p.length)
            root.ok("parse_sorted", p.map(x => x.t).join(",") === "5,13.13,16.56,30,62.5",
                p.map(x => x.t).join(","))
            root.ok("parse_multi_timestamp_line", p[0].text === "Chorus" && p[3].text === "Chorus")
            root.ok("parse_note_line_is_gap", p[2].text === "", JSON.stringify(p[2].text))
            root.ok("index_before_first_line", L.indexAt(p, 4.99) === -1)
            root.ok("index_on_boundary", L.indexAt(p, 13.13) === 1)
            root.ok("index_just_before_boundary", L.indexAt(p, 13.12) === 0)
            root.ok("index_after_last_line", L.indexAt(p, 500) === 4)
            const results = [
                { trackName: "Get Lucky", duration: 248, syncedLyrics: "[00:01.00] x" },
                { trackName: "Blinding Lights", duration: 202, syncedLyrics: "[00:01.00] y" },
                { trackName: "Blinding Lights", duration: 200, syncedLyrics: "" }
            ]
            const a = L.pickSearchResult(results, "Blinding Lights", 201)
            root.ok("search_picks_title_and_duration_match", a !== null && a.duration === 202,
                a ? a.trackName + "@" + a.duration : "null")
            const b = L.pickSearchResult(results, "Blinding Lights", 248)
            root.ok("search_rejects_wrong_song_same_length", b === null, b ? b.trackName : "null")
            const c = L.pickSearchResult(results, "Blinding Lights (Radio Edit)", 202)
            root.ok("search_loose_title_match", c !== null && c.duration === 202, c ? c.trackName : "null")
            const d = L.pickSearchResult(results, "Blinding Lights", 0)
            root.ok("search_unknown_duration_requires_title_and_synced",
                d !== null && d.trackName === "Blinding Lights" && d.syncedLyrics.length > 0)
            const u = L.buildGetUrl("A & B", "C D", 199.6)
            root.ok("url_encodes_and_rounds",
                u.indexOf("track_name=A%20%26%20B") > 0 && u.indexOf("artist_name=C%20D") > 0
                    && u.indexOf("duration=200") > 0, u)
            console.log("=== LYRICS TEST ===")
            for (const line of root.log) console.log(line)
            const failed = root.log.filter(l => l.indexOf("FAIL") === 0).length
            console.log("=== " + (root.log.length - failed) + "/" + root.log.length + " passed ===")
            Qt.exit(failed === 0 ? 0 : 1)
        }
    }
}
