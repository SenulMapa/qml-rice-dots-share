.pragma library

// Pure helpers for the Quick Look preview (mac/MacQuickLook.qml). No QML
// types, so offscreen tests (test-quicklook.qml) cover them directly.

const KIND_EXTENSIONS = {
    image: ["png", "jpg", "jpeg", "gif", "webp", "bmp", "svg", "avif", "heic", "heif", "tif", "tiff", "ico"],
    video: ["mp4", "mkv", "webm", "mov", "avi", "m4v", "ogv", "flv", "wmv"],
    audio: ["mp3", "flac", "ogg", "oga", "opus", "wav", "m4a", "aac", "wma"],
    pdf: ["pdf"],
    text: ["txt", "md", "markdown", "log", "csv", "tsv", "json", "yaml", "yml", "toml", "ini", "conf",
           "cfg", "xml", "html", "htm", "css", "scss", "js", "mjs", "ts", "tsx", "jsx", "qml", "py",
           "sh", "bash", "zsh", "fish", "rs", "go", "c", "h", "cpp", "hpp", "cc", "java", "kt", "swift",
           "rb", "php", "lua", "vim", "sql", "lock", "env", "gitignore", "diff", "patch", "tex", "nix",
           "rst", "srt", "vtt", "ex", "exs", "hs", "ml", "pl", "r", "dart", "vue", "svelte"]
}

// Extension-less files that are plain text in practice.
const TEXT_NAMES = ["makefile", "dockerfile", "license", "readme", "pkgbuild", "changelog",
                    "authors", "todo", "justfile", "gemfile", "rakefile", "procfile"]

function extensionOf(name) {
    const base = String(name).split("/").pop()
    const dot = base.lastIndexOf(".")
    // A leading dot alone (".bashrc") is a name, not an extension.
    if (dot <= 0 || dot === base.length - 1)
        return ""
    return base.slice(dot + 1).toLowerCase()
}

// "image" | "video" | "audio" | "pdf" | "text" | "other"
function kindOf(name) {
    const ext = extensionOf(name)
    for (const kind in KIND_EXTENSIONS) {
        if (ext !== "" && KIND_EXTENSIONS[kind].indexOf(ext) >= 0)
            return kind
    }
    const base = String(name).split("/").pop().toLowerCase()
    if (TEXT_NAMES.indexOf(base) >= 0 || base.indexOf("readme") === 0)
        return "text"
    return "other"
}

// Human label for the "Kind" row: "PNG image", "Folder", "File".
function kindLabel(name, isDirectory) {
    if (isDirectory)
        return "Folder"
    const ext = extensionOf(name)
    const names = { image: "image", video: "video", audio: "audio", pdf: "PDF document", text: "text" }
    const kind = kindOf(name)
    if (kind === "pdf")
        return "PDF document"
    if (kind !== "other")
        return ext ? ext.toUpperCase() + " " + names[kind] : names[kind]
    return ext ? ext.toUpperCase() + " file" : "Document"
}

// Dotfiles are hidden from the folder listing that drives arrow navigation.
function isVisibleName(name) {
    return name.length > 0 && name.charAt(0) !== "."
}

// Visible names only, in a stable order (code-unit compare, like `LC_ALL=C sort`).
function sortNames(names) {
    return names.filter(isVisibleName).sort((a, b) => (a < b ? -1 : a > b ? 1 : 0))
}

// The name `delta` steps from `name` in the sorted list. Clamps at both ends
// (Finder stops at the first and last item rather than wrapping). An unknown
// name yields the first entry, and an empty list yields "".
function neighbour(names, name, delta) {
    if (names.length === 0)
        return ""
    const at = names.indexOf(name)
    if (at < 0)
        return names[0]
    const next = Math.max(0, Math.min(names.length - 1, at + delta))
    return names[next]
}

// Byte count as Finder shows it: "512 bytes", "1.5 KB", "24 MB". Decimal units.
function formatSize(bytes) {
    const n = Number(bytes)
    if (!isFinite(n) || n < 0)
        return ""
    if (n < 1000)
        return Math.round(n) + (Math.round(n) === 1 ? " byte" : " bytes")
    const units = ["KB", "MB", "GB", "TB"]
    let value = n / 1000
    let unit = 0
    while (value >= 1000 && unit < units.length - 1) {
        value /= 1000
        unit++
    }
    const shown = value >= 100 ? Math.round(value).toString() : (Math.round(value * 10) / 10).toString()
    return shown + " " + units[unit]
}

// file:// URL for a local path. Encodes everything a plain encodeURI leaves
// alone that would end the URL early or change its meaning.
function fileUrl(path) {
    return "file://" + encodeURI(String(path)).replace(/#/g, "%23").replace(/\?/g, "%3F")
}

// Directory part of an absolute path ("/a/b/c.txt" -> "/a/b"; "/c.txt" -> "/").
function dirOf(path) {
    const at = String(path).lastIndexOf("/")
    return at <= 0 ? "/" : String(path).slice(0, at)
}

// Final path component.
function nameOf(path) {
    return String(path).split("/").pop()
}

// What a quicklook request means against the current state: "close" when the
// window already shows exactly that path, otherwise "show".
function toggleAction(openPath, requestedPath, isOpen) {
    return isOpen && openPath === requestedPath ? "close" : "show"
}

// Parses `stat -L -c '%s %Y %F'` output: "<bytes> <mtime-epoch> <type words>".
function parseStat(text) {
    const parts = String(text).trim().split(" ")
    if (parts.length < 3)
        return null
    const bytes = parseInt(parts[0], 10)
    const mtime = parseInt(parts[1], 10)
    if (!isFinite(bytes) || !isFinite(mtime))
        return null
    return { bytes: bytes, modifiedMs: mtime * 1000, isDirectory: parts.slice(2).join(" ") === "directory" }
}

// Lines of a text preview, capped. A NUL byte marks the text as binary.
function previewLines(text, maxLines) {
    const raw = String(text)
    if (raw.indexOf("\u0000") >= 0)
        return null
    const lines = raw.split("\n")
    return lines.slice(0, maxLines).join("\n")
}
