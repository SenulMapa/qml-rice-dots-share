.pragma library

// Relative age for banners and Notification Center rows: "now", "5m", "3h", "2d".
function ageText(timestamp, nowMs) {
    const minutes = Math.floor((nowMs - timestamp) / 60000)
    if (minutes < 1)
        return "now"
    if (minutes < 60)
        return minutes + "m"
    const hours = Math.floor(minutes / 60)
    return hours < 24 ? hours + "h" : Math.floor(hours / 24) + "d"
}

// Config.appearance.macScreen: "focused" (default) or an output name such as
// "DP-1". Output names are an open set, so only their shape is checked.
function macScreenValid(value) {
    if (value === "focused")
        return true
    return typeof value === "string" && /^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/.test(value)
}

// The screen a NEW mac surface opens on. A pinned output wins when connected.
// "focused" (or a pinned output that is not connected) uses the Hyprland
// focused monitor, then the primary monitor, then the first screen.
// `screens` is Quickshell.screens (objects with .name); names are plain strings.
function macScreenFor(setting, screens, focusedName, primaryName) {
    const list = screens || []
    if (list.length === 0)
        return null
    const byName = name => (name ? list.find(s => s && s.name === name) : null) || null
    if (setting && setting !== "focused") {
        const pinned = byName(setting)
        if (pinned)
            return pinned
    }
    return byName(focusedName) || byName(primaryName) || list[0]
}

// Config.appearance.macScale: outputWidth / 1440 (Tahoe's reference width in
// pt), clamped to [1.0, 1.6], rounded to 2 decimals. A positive `override`
// (Settings) replaces the computed value. Both paths are clamped.
function macScaleFor(override, outputWidth) {
    // Owner (20 Oct): 1:1 and width/1440 both read "too big" on the 1080p outputs.
    // Default 0.85; an explicit appearance.macScale setting overrides (0.7-1.6).
    const fallback = 0.85
    const minimum = 0.7
    const maximum = 1.6
    let value = Number(override)
    if (!(value > 0) || !isFinite(value))
        value = fallback
    value = Math.max(minimum, Math.min(maximum, value))
    return Math.round(value * 100) / 100
}

// Image URLs that stay valid after the notification is gone. A qsimage
// handle (image://qsimage/...) is transient and must never reach an Image.
function isStableImage(url) {
    if (typeof url !== "string" || url.length === 0)
        return false
    // Local images only: an http(s) image in a notification would make the shell fetch it (IP leak / tracking pixel).
    return url.charAt(0) === "/" || url.indexOf("file://") === 0
}

// MacAvatar source priority:
//   a. the resolved app icon path (Quickshell.iconPath of the app icon,
//      desktop entry icon or app name; "" when none resolves)
//   b. the notification image, only when it is a file path or http(s) URL
//   c. "" -> the letter fallback
function avatarSource(resolvedIconPath, image) {
    if (typeof resolvedIconPath === "string" && resolvedIconPath.length > 0)
        return resolvedIconPath
    return isStableImage(image) ? image : ""
}

// The iPhone battery widget. `status` is PhoneService.status (may be null) and
// `connected` is PhoneService.connected. BlueFerry reports no charging state
// today (status.charging stays null), so "Charging" only appears if a daemon
// ever sends true, and the state reads "Connected" otherwise.
function phoneBatteryLine(status, connected) {
    const device = status && status.device
    const name = device && typeof device.name === "string" && device.name.length > 0
        ? device.name : "iPhone"
    const level = status ? status.battery : null
    const hasLevel = typeof level === "number" && level >= 0 && level <= 100
    const charging = status ? status.charging : null
    let state = "Not connected"
    if (connected) {
        state = charging === true ? "Charging" : charging === false ? "On battery" : "Connected"
    }
    let percent = "Offline"
    if (connected)
        percent = hasLevel ? Math.round(level) + "%" : ""
    return { name: name, percent: percent, state: state }
}

// Spotlight phone intent: "message <name>" / "text <name>" / "call <name>".
// Returns { verb: "message" | "call", target } or null. The target is kept
// as typed (trimmed, 1-64 chars); the daemon checks numbers and contacts.
function phoneIntent(query) {
    const text = String(query || "").trim()
    const match = /^(message|text|call)\s+(.+)$/i.exec(text)
    if (!match)
        return null
    const target = match[2].trim()
    if (target.length === 0 || target.length > 64)
        return null
    return { verb: match[1].toLowerCase() === "call" ? "call" : "message", target: target }
}

// A typed phone number (digits with optional +, spaces, dashes, brackets).
function looksLikeNumber(text) {
    return /^\+?[0-9][0-9 ()-]{2,23}$/.test(String(text || ""))
}

// Spotlight rows for a phone intent. `contacts` are {name, number} hits from
// PhoneService.findContacts. Calls with calls off give one disabled row that
// says why. Rows carry phoneVerb/phoneName/phoneNumber, which MacSpotlightPanel
// reads instead of the palette's execute().
function phoneRows(intent, contacts, enabled, callsEnabled) {
    if (!intent || !enabled)
        return []
    const verbLabel = intent.verb === "call" ? "Call " : "Message "
    if (intent.verb === "call" && !callsEnabled) {
        return [{
            provider: "phone", kind: "phone", badge: "iPhone", enabled: false, executable: false,
            lucide: "phone", title: "Call " + intent.target,
            subtitle: "Calls are off. Turn them on in BlueFerry (blueferry calls enable)."
        }]
    }
    const hits = []
    if (looksLikeNumber(intent.target))
        hits.push({ name: intent.target, number: intent.target })
    for (const contact of (contacts || [])) {
        if (contact && contact.name && contact.number)
            hits.push({ name: String(contact.name), number: String(contact.number) })
    }
    return hits.slice(0, 4).map(hit => ({
        provider: "phone", kind: "phone", badge: "iPhone",
        enabled: true, executable: true,
        lucide: intent.verb === "call" ? "phone" : "message-circle",
        title: verbLabel + hit.name,
        subtitle: hit.number,
        phoneVerb: intent.verb, phoneName: hit.name, phoneNumber: hit.number
    }))
}
