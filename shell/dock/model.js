.pragma library
// Pure dock model: merges pinned apps, running apps (grouped by desktop
// entry) and minimised windows. No QML, no IPC -- the caller passes fake or
// real client lists and a desktop-entry lookup, so it is unit-testable.

var DEFAULT_PIN_TOKENS = ["brave", "kitty", "code", "spotify", "discord", "slack", "thunar"];
// Desktop-id candidates tried (in order) for a default-pin token.
var ALIASES = {
    brave: ["brave-browser", "brave"],
    code: ["code", "code-oss", "visual-studio-code", "com.visualstudio.code"],
    kitty: ["kitty"], spotify: ["spotify"], discord: ["discord"], slack: ["slack"],
    thunar: ["thunar", "org.xfce.thunar"]
};
var HIDDEN_CLASSES = ["quickshell", "org.quickshell"];

function norm(s) { return String(s === undefined || s === null ? "" : s).toLowerCase().replace(/\.desktop$/, ""); }
function lastSegment(id) { var p = norm(id).split("."); return p[p.length - 1]; }

// lookup(id) -> entry|null where entry = {id,name,icon,startupWMClass}
function resolvePin(token, lookup) {
    var cands = ALIASES[norm(token)] || [];
    cands = [token].concat(cands);
    for (var i = 0; i < cands.length; i++) {
        var e = lookup(cands[i]);
        if (e) return e;
    }
    return null;
}

// Resolve a pin list (desktop ids or default tokens) to entries; unresolved
// pins (no .desktop on this machine) are dropped, duplicates removed.
function resolvePins(pins, lookup) {
    var out = [], seen = {};
    for (var i = 0; i < (pins || []).length; i++) {
        var e = resolvePin(pins[i], lookup);
        if (!e) continue;
        var k = norm(e.id);
        if (seen[k]) continue;
        seen[k] = true;
        out.push(e);
    }
    return out;
}

function classMatchesEntry(cls, e) {
    var c = norm(cls);
    if (!c) return false;
    return c === norm(e.id) || c === norm(e.startupWMClass) || c === lastSegment(e.id);
}

function build(o) {
    var lookup = o.lookup || function () { return null; };
    var forClass = o.forClass || function () { return null; };
    var minName = o.minimizedName || "special:minimized";
    var pinEntries = resolvePins(o.pins || [], lookup);
    var launching = o.launching || {};
    var groups = {}, groupOrder = [], minimized = [];

    function keyForClass(cls) {
        var e = forClass(cls);
        if (e) return { key: norm(e.id), entry: e };
        for (var i = 0; i < pinEntries.length; i++)
            if (classMatchesEntry(cls, pinEntries[i])) return { key: norm(pinEntries[i].id), entry: pinEntries[i] };
        return { key: "class:" + norm(cls), entry: null };
    }

    var clients = (o.clients || []).slice().sort(function (a, b) {
        return (a.focusHistoryID === undefined ? 1e6 : a.focusHistoryID) - (b.focusHistoryID === undefined ? 1e6 : b.focusHistoryID);
    });
    for (var i = 0; i < clients.length; i++) {
        var c = clients[i];
        var cls = c["class"] || c.initialClass || "";
        if (!cls || HIDDEN_CLASSES.indexOf(norm(cls)) >= 0) continue;
        if (c.mapped === false) continue;
        if (String(c.title || "").trim().length === 0 && !c.address) continue;
        var kk = keyForClass(cls);
        var g = groups[kk.key];
        if (!g) {
            g = groups[kk.key] = { key: kk.key, entry: kk.entry, cls: cls, addresses: [], windows: [], minimized: [], title: c.title || "" };
            groupOrder.push(kk.key);
        }
        if (c.workspaceName === minName) {
            g.minimized.push(c.address);
            minimized.push({ address: c.address, title: c.title || "", appKey: kk.key, entry: kk.entry, cls: cls });
        } else {
            if (g.addresses.length === 0) g.title = c.title || "";
            g.addresses.push(c.address);
            g.windows.push({ address: c.address, title: c.title || "" });
        }
    }

    function mk(key, entry, cls, pinned) {
        var g = groups[key];
        var windows = g ? g.addresses.length : 0;
        var mins = g ? g.minimized.length : 0;
        var addr = g ? g.addresses : [];
        var focusedHere = !!(o.activeAddress && addr.indexOf(o.activeAddress) >= 0);
        return {
            kind: "app", key: key,
            desktopId: entry ? entry.id : "",
            name: entry ? entry.name : (cls || key),
            icon: entry ? (entry.icon || cls) : cls,
            "class": g ? g.cls : (cls || ""),
            pinned: pinned,
            running: windows + mins > 0,
            windowCount: windows,
            minimizedAddresses: g ? g.minimized.slice() : [],
            addresses: addr.slice(),
            windows: g ? g.windows.slice() : [],
            focused: focusedHere,
            launching: launching[key] !== undefined && windows + mins === 0,
            title: g ? g.title : ""
        };
    }

    var items = [], used = {};
    for (var p = 0; p < pinEntries.length; p++) {
        var pk = norm(pinEntries[p].id);
        used[pk] = true;
        items.push(mk(pk, pinEntries[p], pinEntries[p].icon, true));
    }
    // Running, unpinned: keep first-seen order stable across rebuilds.
    var order = (o.prevOrder || []).filter(function (k) { return groups[k] && !used[k]; });
    for (var q = 0; q < groupOrder.length; q++)
        if (!used[groupOrder[q]] && order.indexOf(groupOrder[q]) < 0) order.push(groupOrder[q]);
    for (var r = 0; r < order.length; r++) {
        var gg = groups[order[r]];
        items.push(mk(order[r], gg.entry, gg.cls, false));
    }
    if (minimized.length > 0) {
        items.push({ kind: "separator", key: "separator" });
        for (var m = 0; m < minimized.length; m++) {
            var mi = minimized[m];
            items.push({ kind: "minimized", key: "min:" + mi.address, address: mi.address,
                         name: mi.title || (mi.entry ? mi.entry.name : mi.cls),
                         icon: mi.entry ? (mi.entry.icon || mi.cls) : mi.cls,
                         appKey: mi.appKey, running: false, pinned: false, focused: false, launching: false });
        }
    }
    return { items: items, order: order };
}

// ---- Hyprland (0.56 Lua) dispatch strings; addresses are validated. ----
function validAddress(a) { return /^0x[0-9a-f]+$/i.test(String(a || "")); }
function q(s) { return JSON.stringify(String(s)); }
function focusCmd(address) {
    return validAddress(address) ? "hl.dsp.focus({ window = " + q("address:" + address) + " })" : "";
}
// Restore a minimised window onto the current workspace, then focus it.
function restoreCmd(address, workspaceId) {
    if (!validAddress(address) || !(Number(workspaceId) > 0)) return "";
    return "hl.dsp.window.move({ workspace = " + Number(workspaceId) + ", window = " + q("address:" + address) + " })";
}
function closeCmd(address) {
    return validAddress(address) ? "hl.dsp.window.close({ window = " + q("address:" + address) + " })" : "";
}

// Next window to focus when an already-focused app is clicked, or when the
// app is cycled from the keyboard (Super+`). focusRanks maps address ->
// focusHistoryID (0 = focused, lower = more recent); windows are cycled in
// that recency order, so repeated presses walk back through the app's windows.
// Without focusRanks the order is by address (stable across calls).
function nextAddress(addresses, activeAddress, focusRanks) {
    if (!addresses || addresses.length === 0) return "";
    var rank = function (a) {
        var r = focusRanks ? Number(focusRanks[a]) : NaN;
        return isFinite(r) ? r : 1e6;
    };
    var s = addresses.slice().sort(function (a, b) {
        return (rank(a) - rank(b)) || (a < b ? -1 : (a > b ? 1 : 0));
    });
    var i = s.indexOf(activeAddress);
    return s[(i + 1) % s.length];
}
