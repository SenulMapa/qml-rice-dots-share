.pragma library
// Pure dock maths. No QML types, no globals, deterministic: the same inputs
// always give the same outputs, so it is unit-tested (test-dock-magnify.qml)
// and the QML only draws what this returns.
//
// Metric object `m` (see DockMetrics.qml for sources):
//   peakScale   scale of the icon directly under the pointer (Mac: 2.0 max)
//   radiusPx    influence radius in px (distance at which scale returns to 1)
//   falloff     "cosine" (default) or "gauss"

var HALF_PI = Math.PI / 2;

// Bell weight in [0,1]: 1 at t=0, 0 for t>=1, smooth (C1) and monotonic.
function bell(t, shape) {
    t = Math.abs(t);
    if (!(t < 1)) return 0;
    if (shape === "gauss") {
        // Gaussian rescaled so it reaches exactly 0 at t=1 (no kink).
        var g = function (x) { return Math.exp(-(x * x) * 4.5); };
        var g1 = g(1);
        return (g(t) - g1) / (1 - g1);
    }
    return 0.5 * (1 + Math.cos(Math.PI * t));
}

function scaleAt(distance, m) {
    var w = bell(distance / m.radiusPx, m.falloff);
    return 1 + (m.peakScale - 1) * w;
}

// pointerX   pointer x in the same coordinate space as `centers` (null/NaN =
//            pointer not over the dock: everything rests at scale 1)
// centers[]  rest-layout slot centres (contiguous slots, left to right)
// widths[]   rest slot widths
// magnifiable[] optional booleans; false = never scales (separators)
// amount     0..1 blend between rest and fully magnified (enter/leave ramp)
//
// Returns { scales, widths, centers, offsets, left, restLeft, extra }
//   widths   magnified slot widths (rest width * scale)
//   centers  magnified slot centres. The dock widens symmetrically about its
//            rest centre, like macOS.
//   offsets  centers[i] - rest centre[i]
//   extra    total width gained = sum(restWidth * (scale - 1))
function magnify(pointerX, centers, widths, m, magnifiable, amount) {
    var n = centers.length;
    var amt = amount === undefined || amount === null ? 1 : Math.max(0, Math.min(1, amount));
    var scales = new Array(n), outW = new Array(n), outC = new Array(n), offs = new Array(n);
    var active = typeof pointerX === "number" && isFinite(pointerX) && amt > 0;
    var restLeft = n > 0 ? centers[0] - widths[0] / 2 : 0;
    var extra = 0, i;
    for (i = 0; i < n; i++) {
        var s = 1;
        if (active && (!magnifiable || magnifiable[i] !== false))
            s = 1 + (scaleAt(pointerX - centers[i], m) - 1) * amt;
        scales[i] = s;
        outW[i] = widths[i] * s;
        extra += widths[i] * (s - 1);
    }
    var restTotal = 0;
    for (i = 0; i < n; i++) restTotal += widths[i];
    var left = restLeft - extra / 2;
    var x = left;
    for (i = 0; i < n; i++) {
        outC[i] = x + outW[i] / 2;
        offs[i] = outC[i] - centers[i];
        x += outW[i];
    }
    return { scales: scales, widths: outW, centers: outC, offsets: offs,
             left: left, restLeft: restLeft, restTotal: restTotal, extra: extra };
}

// Rest layout from slot widths, left edge at x0.
function restLayout(widths, x0) {
    var c = [], x = x0 || 0;
    for (var i = 0; i < widths.length; i++) { c.push(x + widths[i] / 2); x += widths[i]; }
    return { centers: c, total: x - (x0 || 0) };
}

// Exact critically-damped follow (no integration error for any dt).
// Returns [position, velocity]. omega ~ 4.6/settleTime.
function smoothDamp(current, target, velocity, omega, dt) {
    var x = current - target;
    var e = Math.exp(-omega * dt);
    var tmp = (velocity + omega * x) * dt;
    return [target + (x + tmp) * e, (velocity - omega * tmp) * e];
}

// Launch bounce: height (fraction of tile height) at time t seconds.
// Each period is an ease-out rise (first half) then an ease-in fall (second
// half); `restFraction` of the period is spent on the ground between bounces.
function bounce(t, m) {
    if (!(t >= 0)) return 0;
    var T = m.bouncePeriod;
    var active = T * (1 - (m.bounceRestFraction || 0));
    var ph = t - Math.floor(t / T) * T;
    if (ph >= active) return 0;
    var u = ph / active;
    var h = u < 0.5
        ? 1 - Math.pow(1 - 2 * u, 2)          // ease-out up
        : 1 - Math.pow(2 * u - 1, 2);         // ease-in down
    return m.bounceHeight * h;
}

// Index of the rest slot a dragged x lands in (for reorder).
function slotIndexAt(x, centers, widths) {
    var n = centers.length;
    for (var i = 0; i < n; i++)
        if (x < centers[i] + widths[i] / 2) return i;
    return Math.max(0, n - 1);
}
