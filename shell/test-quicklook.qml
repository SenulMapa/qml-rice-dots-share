// Unit tests for the Quick Look pure helpers (mac/QuickLookFormat.js): file
// kind detection, folder neighbours for arrow navigation, sizes, URLs and the
// toggle decision. Pure logic only: no file is read, opened or rendered.
import QtQuick
import "mac/QuickLookFormat.js" as QL

Item {
    id: root
    property var log: []
    function ok(name, cond, detail) {
        log.push((cond ? "PASS  " : "FAIL  ") + name + (detail ? "   " + detail : ""))
    }
    function eq(name, got, want) {
        ok(name, got === want, "got " + JSON.stringify(got) + ", want " + JSON.stringify(want))
    }

    Component.onCompleted: {
        // Kinds by extension, case-insensitive.
        const kinds = {
            "photo.PNG": "image", "a.jpeg": "image", "clip.mkv": "video", "clip.MP4": "video",
            "song.flac": "audio", "voice.opus": "audio", "paper.pdf": "pdf", "PAPER.PDF": "pdf",
            "main.qml": "text", "notes.md": "text", "data.json": "text", "archive.zip": "other",
            "binary.bin": "other", "Makefile": "text", "README": "text", "LICENSE": "text",
            "PKGBUILD": "text", "noext": "other", ".bashrc": "other", "dir.name/file": "other",
            "trailing.": "other", "x.Png.zip": "other"
        }
        for (const name in kinds)
            eq("kind_" + name, QL.kindOf(name), kinds[name])

        // Extension helper: dotfiles and trailing dots have none.
        eq("ext_dotfile", QL.extensionOf(".env"), "")
        eq("ext_plain", QL.extensionOf("a.tar.gz"), "gz")
        eq("ext_trailing_dot", QL.extensionOf("a."), "")

        // Kind labels for the metadata row.
        eq("label_folder", QL.kindLabel("anything", true), "Folder")
        eq("label_png", QL.kindLabel("a.png", false), "PNG image")
        eq("label_pdf", QL.kindLabel("a.pdf", false), "PDF document")
        eq("label_other_ext", QL.kindLabel("a.zip", false), "ZIP file")
        eq("label_noext", QL.kindLabel("noext", false), "Document")

        // Folder listing: dotfiles dropped, stable order.
        const listed = QL.sortNames([".hidden", "b.txt", "", "A.png", "c.txt", "a.txt"])
        eq("sort_hides_dotfiles_and_empty", listed.join("|"), "A.png|a.txt|b.txt|c.txt")

        // Arrow navigation: clamps at both ends, no wrap.
        const names = ["a.png", "b.mp4", "c.pdf"]
        eq("next_from_first", QL.neighbour(names, "a.png", 1), "b.mp4")
        eq("next_from_last_clamps", QL.neighbour(names, "c.pdf", 1), "c.pdf")
        eq("prev_from_first_clamps", QL.neighbour(names, "a.png", -1), "a.png")
        eq("prev_from_last", QL.neighbour(names, "c.pdf", -1), "b.mp4")
        eq("unknown_name_first", QL.neighbour(names, "gone.txt", 1), "a.png")
        eq("empty_folder", QL.neighbour([], "x", 1), "")
        eq("single_file_stays", QL.neighbour(["only"], "only", 1), "only")

        // Sizes, decimal units like Finder.
        eq("size_zero", QL.formatSize(0), "0 bytes")
        eq("size_one", QL.formatSize(1), "1 byte")
        eq("size_bytes", QL.formatSize(999), "999 bytes")
        eq("size_kb", QL.formatSize(1500), "1.5 KB")
        eq("size_kb_round", QL.formatSize(12345), "12.3 KB")
        eq("size_hundreds", QL.formatSize(254000), "254 KB")
        eq("size_mb", QL.formatSize(24 * 1000 * 1000), "24 MB")
        eq("size_gb", QL.formatSize(3.2e9), "3.2 GB")
        eq("size_negative", QL.formatSize(-1), "")

        // URLs: spaces, hash and question mark must survive as one path.
        eq("url_plain", QL.fileUrl("/home/u/a.png"), "file:///home/u/a.png")
        eq("url_space", QL.fileUrl("/home/u/my file.png"), "file:///home/u/my%20file.png")
        eq("url_hash_q", QL.fileUrl("/x/#a?b.png"), "file:///x/%23a%3Fb.png")

        // Path helpers.
        eq("dir_of", QL.dirOf("/a/b/c.txt"), "/a/b")
        eq("dir_of_root_child", QL.dirOf("/c.txt"), "/")
        eq("name_of", QL.nameOf("/a/b/c.txt"), "c.txt")

        // Toggle: the same path closes, any other path shows.
        eq("toggle_same_open", QL.toggleAction("/a.png", "/a.png", true), "close")
        eq("toggle_other_open", QL.toggleAction("/a.png", "/b.png", true), "show")
        eq("toggle_closed", QL.toggleAction("/a.png", "/a.png", false), "show")

        // stat output: size, mtime (epoch seconds), type words.
        const st = QL.parseStat("2048 1700000000 regular file\n")
        ok("stat_parse", st && st.bytes === 2048 && st.modifiedMs === 1700000000000 && !st.isDirectory)
        ok("stat_dir", QL.parseStat("4096 1700000000 directory").isDirectory === true)
        eq("stat_garbage", QL.parseStat("nope"), null)

        // Text preview: capped at N lines, binary (NUL) rejected.
        const many = []
        for (let i = 0; i < 250; i++) many.push("line " + i)
        const capped = QL.previewLines(many.join("\n"), 200).split("\n")
        ok("preview_capped", capped.length === 200 && capped[199] === "line 199")
        eq("preview_binary", QL.previewLines("ab\u0000cd", 200), null)
        eq("preview_short", QL.previewLines("one\ntwo", 200), "one\ntwo")

        console.log("=== QUICKLOOK TEST ===")
        for (const line of log) console.log(line)
        const failed = log.filter(l => l.startsWith("FAIL")).length
        console.log("=== " + (log.length - failed) + "/" + log.length + " passed ===")
        Qt.quit()
    }
}
