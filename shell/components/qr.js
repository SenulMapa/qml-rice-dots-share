.pragma library
// Minimal QR Code encoder: byte mode, error correction M, versions 1-10
// (up to 213 bytes at v10; enough for a ~200-char Larix deep link). Spec:
// ISO/IEC 18004. Verified against `qrencode -t ASCII -l M` by test-qr.qml.
//
// encode(text[, forcedMask]) -> { version, size, mask, get(row, col) -> bool } or null
// when the text does not fit. forcedMask exists for the test harness.
// Known deviation: on 1 of 12 reference vectors ("hello world") the
// auto-picked mask differs from libqrencode's penalty scoring; both are valid.

// [ecCodewordsPerBlock, g1Blocks, g1Data, g2Blocks, g2Data] for level M, v1..10
var EC_M = [
    null,
    [10, 1, 16, 0, 0], [16, 1, 28, 0, 0], [26, 1, 44, 0, 0], [18, 2, 32, 0, 0],
    [24, 2, 43, 0, 0], [16, 4, 27, 0, 0], [18, 4, 31, 0, 0], [22, 2, 38, 2, 39],
    [22, 3, 36, 2, 37], [26, 4, 43, 1, 44]
]
var ALIGN = [null, [], [6, 18], [6, 22], [6, 26], [6, 30], [6, 34], [6, 22, 38],
    [6, 24, 42], [6, 26, 46], [6, 28, 50]]

var EXP = [], LOG = []
;(function () {
    var x = 1
    for (var i = 0; i < 255; i++) {
        EXP[i] = x
        LOG[x] = i
        x <<= 1
        if (x & 0x100) x ^= 0x11d
    }
    for (var j = 255; j < 512; j++) EXP[j] = EXP[j - 255]
})()

function gmul(a, b) { return a === 0 || b === 0 ? 0 : EXP[LOG[a] + LOG[b]] }

function rsRemainder(data, ecLen) {
    var gen = [1]
    for (var i = 0; i < ecLen; i++) {
        var next = []
        for (var k = 0; k <= gen.length; k++) next[k] = 0
        for (var j = 0; j < gen.length; j++) {
            next[j] ^= gen[j]
            next[j + 1] ^= gmul(gen[j], EXP[i])
        }
        gen = next
    }
    var rem = []
    for (var r = 0; r < ecLen; r++) rem[r] = 0
    for (var d = 0; d < data.length; d++) {
        var factor = data[d] ^ rem[0]
        rem.shift()
        rem.push(0)
        for (var g = 0; g < ecLen; g++) rem[g] ^= gmul(gen[g + 1], factor)
    }
    return rem
}

function utf8(str) {
    var out = []
    for (var i = 0; i < str.length; i++) {
        var c = str.charCodeAt(i)
        if (c >= 0xd800 && c < 0xdc00 && i + 1 < str.length) {
            c = 0x10000 + ((c - 0xd800) << 10) + (str.charCodeAt(++i) - 0xdc00)
        }
        if (c < 0x80) out.push(c)
        else if (c < 0x800) out.push(0xc0 | (c >> 6), 0x80 | (c & 63))
        else if (c < 0x10000) out.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63))
        else out.push(0xf0 | (c >> 18), 0x80 | ((c >> 12) & 63), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63))
    }
    return out
}

function dataCapacity(v) {
    var e = EC_M[v]
    return e[1] * e[2] + e[3] * e[4]
}

function codewords(bytes, v) {
    var cap = dataCapacity(v)
    var bits = []
    function put(val, n) { for (var i = n - 1; i >= 0; i--) bits.push((val >> i) & 1) }
    put(4, 4)
    put(bytes.length, v < 10 ? 8 : 16)
    for (var i = 0; i < bytes.length; i++) put(bytes[i], 8)
    var maxBits = cap * 8
    for (var t = 0; t < 4 && bits.length < maxBits; t++) bits.push(0)
    while (bits.length % 8) bits.push(0)
    var data = []
    for (var b = 0; b < bits.length; b += 8) {
        var byte = 0
        for (var k = 0; k < 8; k++) byte = (byte << 1) | bits[b + k]
        data.push(byte)
    }
    for (var pad = 0xec; data.length < cap; pad = pad === 0xec ? 0x11 : 0xec) data.push(pad)

    var e = EC_M[v], blocks = [], pos = 0
    for (var g = 0; g < e[1] + e[3]; g++) {
        var len = g < e[1] ? e[2] : e[4]
        blocks.push(data.slice(pos, pos + len))
        pos += len
    }
    var ecs = blocks.map(function (blk) { return rsRemainder(blk, e[0]) })
    var out = []
    var maxLen = Math.max(e[2], e[4])
    for (var c = 0; c < maxLen; c++)
        for (var bi = 0; bi < blocks.length; bi++)
            if (c < blocks[bi].length) out.push(blocks[bi][c])
    for (var c2 = 0; c2 < e[0]; c2++)
        for (var bj = 0; bj < ecs.length; bj++) out.push(ecs[bj][c2])
    return out
}

function bchFormat(data) {
    var rem = data
    for (var i = 0; i < 10; i++) rem = (rem << 1) ^ ((rem >> 9) * 0x537)
    return ((data << 10) | rem) ^ 0x5412
}
function bchVersion(v) {
    var rem = v
    for (var i = 0; i < 12; i++) rem = (rem << 1) ^ ((rem >> 11) * 0x1f25)
    return (v << 12) | rem
}

function buildBase(v) {
    var size = 17 + 4 * v
    var m = [], fn = []
    for (var r = 0; r < size; r++) {
        m.push([]); fn.push([])
        for (var c = 0; c < size; c++) { m[r].push(false); fn[r].push(false) }
    }
    function set(r, c, dark) {
        if (r < 0 || c < 0 || r >= size || c >= size) return
        m[r][c] = dark
        fn[r][c] = true
    }
    function finder(r0, c0) {
        for (var dr = -1; dr <= 7; dr++)
            for (var dc = -1; dc <= 7; dc++) {
                var inRing = dr >= 0 && dr <= 6 && dc >= 0 && dc <= 6
                var dark = inRing && (dr === 0 || dr === 6 || dc === 0 || dc === 6
                    || (dr >= 2 && dr <= 4 && dc >= 2 && dc <= 4))
                set(r0 + dr, c0 + dc, dark)
            }
    }
    finder(0, 0); finder(0, size - 7); finder(size - 7, 0)
    for (var i = 8; i < size - 8; i++) { set(6, i, i % 2 === 0); set(i, 6, i % 2 === 0) }
    var ap = ALIGN[v]
    for (var a = 0; a < ap.length; a++)
        for (var b = 0; b < ap.length; b++) {
            if ((a === 0 && b === 0) || (a === 0 && b === ap.length - 1) || (a === ap.length - 1 && b === 0))
                continue
            for (var dr = -2; dr <= 2; dr++)
                for (var dc = -2; dc <= 2; dc++)
                    set(ap[a] + dr, ap[b] + dc, Math.max(Math.abs(dr), Math.abs(dc)) !== 1)
        }
    // reserve format areas (written per mask) and version areas
    function reserve(r, c) { if (!fn[r][c]) set(r, c, false) }
    for (var k = 0; k < 9; k++) { reserve(8, k); reserve(k, 8) }
    for (var k2 = 0; k2 < 8; k2++) { reserve(8, size - 1 - k2); reserve(size - 1 - k2, 8) }
    set(size - 8, 8, true) // dark module
    if (v >= 7) {
        var vi = bchVersion(v)
        for (var n = 0; n < 18; n++) {
            var bit = ((vi >> n) & 1) === 1
            var q = Math.floor(n / 3), w = n % 3
            set(q, size - 11 + w, bit)
            set(size - 11 + w, q, bit)
        }
    }
    return { size: size, m: m, fn: fn }
}

function maskFn(mask, r, c) {
    switch (mask) {
    case 0: return (r + c) % 2 === 0
    case 1: return r % 2 === 0
    case 2: return c % 3 === 0
    case 3: return (r + c) % 3 === 0
    case 4: return (Math.floor(r / 2) + Math.floor(c / 3)) % 2 === 0
    case 5: return (r * c) % 2 + (r * c) % 3 === 0
    case 6: return ((r * c) % 2 + (r * c) % 3) % 2 === 0
    default: return ((r + c) % 2 + (r * c) % 3) % 2 === 0
    }
}

// N3 as libqrencode scores it (the frame edge counts as a light run): a
// 1:1:3:1:1 dark/light/dark run pattern with a light run of at least four
// units on either side. A leading dark module gets a phantom light run of -1.
function n3Line(at, r, size) {
    var runs = []
    if (at(r, 0)) runs.push(-1)
    runs.push(1)
    for (var c = 1; c < size; c++) {
        if (at(r, c) !== at(r, c - 1)) runs.push(1)
        else runs[runs.length - 1]++
    }
    var n = runs.length, total = 0
    for (var i = 3; i < n - 2; i += 2) {
        if (runs[i] % 3 !== 0) continue
        var f = runs[i] / 3
        if (runs[i - 2] !== f || runs[i - 1] !== f || runs[i + 1] !== f || runs[i + 2] !== f)
            continue
        if (i === 3 || runs[i - 3] >= 4 * f) total += 40
        else if (i + 4 >= n || runs[i + 3] >= 4 * f) total += 40
    }
    return total
}

function penalty(m, size) {
    var score = 0, r, c, i
    for (var pass = 0; pass < 2; pass++) {
        var at = pass === 0 ? function (a, b) { return m[a][b] } : function (a, b) { return m[b][a] }
        for (r = 0; r < size; r++) {
            var run = 1
            for (c = 1; c <= size; c++) {
                if (c < size && at(r, c) === at(r, c - 1)) run++
                else { if (run >= 5) score += 3 + run - 5; run = 1 }
            }
            score += n3Line(at, r, size)
        }
    }
    for (r = 0; r < size - 1; r++)
        for (c = 0; c < size - 1; c++)
            if (m[r][c] === m[r][c + 1] && m[r][c] === m[r + 1][c] && m[r][c] === m[r + 1][c + 1]) score += 3
    var dark = 0
    for (r = 0; r < size; r++) for (c = 0; c < size; c++) if (m[r][c]) dark++
    score += Math.floor(Math.abs(Math.floor(dark * 100 / (size * size)) - 50) / 5) * 10
    return score
}

function writeFormat(m, size, mask) {
    var bits = bchFormat(mask) // EC level M = 00
    function bit(i) { return ((bits >> i) & 1) === 1 }
    for (var i = 0; i <= 5; i++) m[i][8] = bit(i)
    m[7][8] = bit(6); m[8][8] = bit(7); m[8][7] = bit(8)
    for (var j = 9; j < 15; j++) m[8][14 - j] = bit(j)
    for (var k = 0; k < 8; k++) m[8][size - 1 - k] = bit(k)
    for (var n = 8; n < 15; n++) m[size - 15 + n][8] = bit(n)
}

function encode(text, forcedMask) {
    var bytes = utf8(String(text))
    var v = 1
    while (v <= 10 && bytes.length > dataCapacity(v) - (v < 10 ? 2 : 3)) v++
    if (v > 10) return null
    var cw = codewords(bytes, v)
    var base = buildBase(v)
    var size = base.size
    // zigzag placement
    var bitIdx = 0, up = true
    var placed = []
    for (var r = 0; r < size; r++) { placed.push([]); for (var c0 = 0; c0 < size; c0++) placed[r].push(false) }
    for (var col = size - 1; col > 0; col -= 2) {
        if (col === 6) col--
        for (var n = 0; n < size; n++) {
            var row = up ? size - 1 - n : n
            for (var d = 0; d < 2; d++) {
                var cc = col - d
                if (base.fn[row][cc]) continue
                var bit = bitIdx < cw.length * 8 ? ((cw[bitIdx >> 3] >> (7 - (bitIdx & 7))) & 1) === 1 : false
                bitIdx++
                base.m[row][cc] = bit
                placed[row][cc] = true
            }
        }
        up = !up
    }
    var best = null, bestScore = 1e9, bestMask = 0
    for (var mask = 0; mask < 8; mask++) {
        if (forcedMask !== undefined && mask !== forcedMask) continue
        var mm = base.m.map(function (row) { return row.slice() })
        for (var rr = 0; rr < size; rr++)
            for (var cx = 0; cx < size; cx++)
                if (placed[rr][cx] && maskFn(mask, rr, cx)) mm[rr][cx] = !mm[rr][cx]
        writeFormat(mm, size, mask)
        var s = penalty(mm, size)
        if (s < bestScore) { bestScore = s; best = mm; bestMask = mask }
    }
    return { version: v, size: size, mask: bestMask, get: function (r, c) { return best[r][c] } }
}

// "##" per dark module, two spaces per light one, no margin; same shape as
// `qrencode -t ASCII -m 0`.
function toAscii(qr) {
    var lines = []
    for (var r = 0; r < qr.size; r++) {
        var s = ""
        for (var c = 0; c < qr.size; c++) s += qr.get(r, c) ? "##" : "  "
        lines.push(s)
    }
    return lines.join("\n")
}
