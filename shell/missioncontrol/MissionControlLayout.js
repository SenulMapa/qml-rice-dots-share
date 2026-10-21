.pragma library

// Mission Control geometry: pure JS, no QML imports, so
// test-mission-layout.qml can exercise it offscreen.
//
// pack(items, area, gap): items are {w, h} in reading order. Returns one
// {x, y, w, h} slot per item, in the same order. Slots keep each item's
// aspect ratio, never overlap, and stay inside `area` ({x, y, w, h}).
//
// The packer tries every row count r from 1 to n. For each r the items are
// split into r contiguous rows of near-equal count (earlier rows take the
// extra item). Every row shares one height, chosen so the row fills the full
// width of the area. A stack taller than the area is scaled down as a whole
// and centred. The r that covers the most window area wins. Ties go to the
// smaller r, so the result is deterministic for a given input.

var FALLBACK_ASPECT = 16 / 10;

function aspectOf(item) {
    var w = Number(item.w), h = Number(item.h);
    return (w > 0 && h > 0) ? w / h : FALLBACK_ASPECT;
}

function splitRows(n, r) {
    var rows = [];
    var base = Math.floor(n / r);
    var extra = n % r;
    var start = 0;
    for (var i = 0; i < r; i++) {
        var count = base + (i < extra ? 1 : 0);
        rows.push({ start: start, count: count });
        start += count;
    }
    return rows;
}

// Unscaled layout for exactly r rows. Returns null when a row cannot fit its gaps.
function layoutRows(items, width, gap, r) {
    var rows = splitRows(items.length, r);
    var rowHeights = [];
    var stackHeight = 0;
    var coverage = 0;
    for (var k = 0; k < rows.length; k++) {
        var row = rows[k];
        var sumA = 0;
        for (var i = row.start; i < row.start + row.count; i++)
            sumA += aspectOf(items[i]);
        var rowWidth = width - (row.count - 1) * gap;
        if (rowWidth <= 0 || sumA <= 0)
            return null;
        var h = rowWidth / sumA;
        rowHeights.push(h);
        stackHeight += h;
        coverage += h * rowWidth;
    }
    stackHeight += (rows.length - 1) * gap;
    return { rows: rows, rowHeights: rowHeights, stackHeight: stackHeight, coverage: coverage };
}

function pack(items, area, gap) {
    var n = items.length;
    if (n === 0)
        return [];
    var g = Math.max(0, Number(gap) || 0);
    var W = Math.max(0, Number(area.w) || 0);
    var H = Math.max(0, Number(area.h) || 0);

    var best = null;
    for (var r = 1; r <= n; r++) {
        var lay = layoutRows(items, W, g, r);
        if (!lay)
            continue;
        var f = lay.stackHeight > 0 ? Math.min(1, H / lay.stackHeight) : 1;
        var score = f * f * lay.coverage;
        if (!best || score > best.score + 1e-9)
            best = { lay: lay, f: f, score: score };
    }
    if (!best) {
        var empty = [];
        for (var e = 0; e < n; e++)
            empty.push({ x: area.x, y: area.y, w: 0, h: 0 });
        return empty;
    }

    var lay2 = best.lay;
    var f2 = best.f;
    var contentW = W * f2;
    var contentH = lay2.stackHeight * f2;
    var ox = area.x + (W - contentW) / 2;
    var oy = area.y + (H - contentH) / 2;
    var slots = new Array(n);
    var y = 0;
    for (var k2 = 0; k2 < lay2.rows.length; k2++) {
        var row = lay2.rows[k2];
        var h = lay2.rowHeights[k2];
        var x = 0;
        for (var i2 = row.start; i2 < row.start + row.count; i2++) {
            var w = aspectOf(items[i2]) * h;
            slots[i2] = { x: ox + f2 * x, y: oy + f2 * y, w: f2 * w, h: f2 * h };
            x += w + g;
        }
        y += h + g;
    }
    return slots;
}

// Indices of rects in reading order: by centre y, then centre x, then index.
function readingOrder(rects) {
    var idx = [];
    for (var i = 0; i < rects.length; i++)
        idx.push(i);
    idx.sort(function (a, b) {
        var ra = rects[a], rb = rects[b];
        var dy = (ra.y + ra.h / 2) - (rb.y + rb.h / 2);
        if (Math.abs(dy) > 1e-6)
            return dy;
        var dx = (ra.x + ra.w / 2) - (rb.x + rb.w / 2);
        if (Math.abs(dx) > 1e-6)
            return dx;
        return a - b;
    });
    return idx;
}

// ---- Hyprland (Lua) dispatch strings; addresses are validated first. ----
function validAddress(a) {
    return /^0x[0-9a-f]+$/i.test(String(a || ""));
}

function q(s) {
    return JSON.stringify(String(s));
}

function focusCmd(address) {
    return validAddress(address)
        ? "hl.dsp.focus({ window = " + q("address:" + address) + " })" : "";
}

// Silent move (follow = false) so Mission Control stays on the current workspace.
function moveCmd(address, workspaceId) {
    var ws = Number(workspaceId);
    if (!validAddress(address) || !(ws > 0) || ws !== Math.floor(ws))
        return "";
    return "hl.dsp.window.move({ workspace = " + ws + ", follow = false, window = "
        + q("address:" + address) + " })";
}
