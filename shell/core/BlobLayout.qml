pragma Singleton
import QtQuick
import "."

/**
 * BlobLayout — pure geometry for the one-pill blob engine
 * (docs/superpowers/specs/2026-09-23-blob-rebuild-design.md section 1).
 *
 * `targets(state, screen, ctx)` maps a state name + screen size + small
 * context object onto up to 4 body rects (pill, left satellite, right
 * satellite, spare) plus per-pair neck factors. It is a PURE function: no
 * bindings to live Config/IslandController state beyond what's passed in
 * `ctx`, so it is trivially unit-testable (test-blob-layout.qml) and so the
 * shader/BlobSurface layer never needs to know *why* a body is a given
 * size, only what size it is right now.
 *
 * UNIT. `unit(screen) = clamp(min(screen.width, screen.height) * 44/1080, 30,
 * 64)`. At 1920x1080 this reproduces the historical 44px Theme.unit exactly.
 * On the rotated 1080x1920 portrait monitor, min(w,h) is still 1080, so the
 * unit (and therefore every k*unit size) is IDENTICAL to the landscape
 * screen -- only the available width for centring/clamping differs. Every
 * body size below is `k * unit`, with k taken from (or matching)
 * Config.island's existing ratios so the on-screen sizes don't jump when
 * this replaces the old per-state Config-literal lookups.
 *
 * STATES implemented: "rest", "hover", "media", "osd", "notification",
 * "dashboard" (alias "expanded"). Placeholder hooks left for phases B/C/D:
 * "subpage" (notes/todo/pet) and "settings" both return a sized, empty
 * content slot the same shape as "dashboard" so a later phase only needs to
 * fill content, not touch geometry.
 *
 * BODIES. bodies[0] is always the pill. bodies[1]/bodies[2] are the left/
 * right satellites (Wi-Fi left, Bluetooth/Audio right per the spec) --
 * present (w>0 && h>0) only when ctx.wifiOpen / ctx.bluetoothOpen ||
 * ctx.audioOpen is true. bodies[3] is reserved/unused (spare slot the
 * shader supports but nothing currently targets). A body with w<=0 or
 * h<=0 must be treated by the shader/BlobSurface as absent.
 */
QtObject {
    id: root

    readonly property real minUnit: 30
    readonly property real maxUnit: 64
    readonly property real refUnit: 44
    readonly property real refDim: 1080

    function unit(screen) {
        const w = screen && screen.width ? screen.width : 1920
        const h = screen && screen.height ? screen.height : 1080
        const raw = Math.min(w, h) * root.refUnit / root.refDim
        // DisplayScale (core/DisplayScale.qml): this formula is screen-
        // RESOLUTION-based, not DPI-based, so a 1080p desktop monitor and a
        // 1080p laptop panel got the identical unit despite the laptop's
        // pixels being physically smaller (measured 157 vs ~92 PPI on this
        // machine, 59% of the intended physical size). Scale the raw value
        // AND the clamp bounds by the same per-screen factor so a very
        // small/large panel's floor/ceiling scale with it too, then round
        // once at the end -- every k*unit caller downstream already expects
        // a size in device pixels.
        const scale = DisplayScale.forScreen(screen)
        return Math.round(Math.max(root.minUnit * scale,
            Math.min(root.maxUnit * scale, raw * scale)))
    }

    // ---- ink droplet (Config.appearance.ink, ctx.inkDetach) -------------
    // Each satellite is driven by ONE detach progress p (a MotionValue in
    // Island.qml, bouncy preset): 0 = fully merged into the pill edge, 1 =
    // resting gap, >1 while the spring overshoots. Everything else derives
    // from p, so the liquid choreography is one spring, not timers.
    //   inkDetachGap     resting gap between pill edge and satellite (x unit)
    //   inkMergeOverlap  how far a merged satellite sits inside the pill (x unit)
    //   inkSnapLo/Hi     neck fades from full to zero across this band of the
    //                    gap (x inkDetachGap): the "snap" when it floats free
    //   inkNeckBoost     extra neck k at mid-travel so the stretch reads liquid
    // The snap band is deliberately BELOW the resting gap: a blend radius of
    // 1.2u (~53px) would never release at a 14px rest gap.
    readonly property real inkDetachGap: 0.32
    readonly property real inkMergeOverlap: 0.5
    readonly property real inkSnapLo: 0.2
    readonly property real inkSnapHi: 0.6
    readonly property real inkNeckBoost: 0.3

    // Satellite rect + neck for one side. side < 0 = left (Wi-Fi), > 0 =
    // right. edgeX is the pill edge the satellite hangs off (left edge for
    // left, right edge for right). Size and travel both scale with p, so the
    // body is a point-like bulge at p~0 and a full satellite at p=1.
    function inkSatellite(side, p, edgeX, satW, hT, u, screen) {
        const s = Math.max(0, Math.min(1, p))
        const e = root.inkMergeOverlap * u * (1 - p) - root.inkDetachGap * u * p
        const gap = -e                       // >0 = detached by this many px
        const w = satW * s
        const h = hT * s
        let x = side < 0 ? edgeX + e - w : edgeX - e
        x = Math.max(0, Math.min(screen.width - w, x))
        const g = root.inkDetachGap * u
        const fadeT = Math.max(0, Math.min(1,
            (gap - root.inkSnapLo * g) / Math.max(1e-6, (root.inkSnapHi - root.inkSnapLo) * g)))
        const fade = 1 - fadeT
        const boost = 1 + root.inkNeckBoost * 4 * s * (1 - s)
        return {
            body: { x: x, y: 0, w: w, h: h, r: Math.min(h / 2, 0.5 * u) },
            gap: gap,
            neck: 1.2 * u * boost * fade
        }
    }

    // Screen-width-aware clamp for a portrait or narrow monitor: a body
    // may never exceed screen.width - 2*unit (keeps a full-unit margin on
    // both sides even on a rotated 1080-wide-by-1920-tall output).
    function clampWidth(w, screen, u) {
        const sw = screen && screen.width ? screen.width : 1920
        return Math.max(0, Math.min(w, sw - 2 * u))
    }
    function clampHeight(h, screen, u) {
        const sh = screen && screen.height ? screen.height : 1080
        return Math.max(0, Math.min(h, sh * 0.9))
    }

    function emptyBody() {
        return { x: 0, y: 0, w: 0, h: 0, r: 0 }
    }

    // ---- content ratio tokens -------------------------------------------
    // One shared rhythm for everything laid out INSIDE a pill (workspace
    // row slots, the rest clock/eq/lyric row's end padding, the hover
    // row), all scaled off that state's own pill height h -- not a
    // hardcoded pixel value and not the global Theme unit, which doesn't
    // track a specific pill's actual current height. Before this, island/
    // WorkspacePillRow.qml hand-picked Theme.u(0.62)/Theme.u(0.14) for its
    // slot/gap and island/IslandRestItem.qml separately hand-picked
    // `Config.island.dormantHeight * 0.4` for endPad -- two uncoordinated
    // ratios that happened to look similar but drifted independently, and
    // WorkspacePillRow's own icon (`width * 0.7`) vs number
    // (`10 * restTextScale`, a flat pixel size unrelated to slot size)
    // glyph sizes had no shared ratio at all, which is what actually read
    // as "uneven" in the workspace row (owner's screenshot: icons and bare
    // numbers visibly different weights, inconsistent gaps) even though
    // the slots themselves were already equal width. Tuned by eye against
    // captures (see docs/superpowers -- pill-workspace-row-*.png).
    readonly property real kSlot: 0.62   // workspace slot width/height
    readonly property real kGap: 0.14    // gap between adjacent slots/items
    readonly property real kPad: 0.36    // edge padding, row start/end
    readonly property real kIcon: 0.5    // icon glyph size within a slot
    readonly property real kText: 0.36   // number/text glyph size within a slot

    /** n equal-width slots + (n-1) inter-slot gaps + padding on both ends,
     *  all scaled off pill height h -- the row's OWN width. A pill sized
     *  to fit this row derives its width FROM this, never the other way
     *  round (a row must never re-flow because its container happened to
     *  be a different width that frame). */
    function rowWidth(n, h) {
        return Math.max(1, n) * (h * root.kSlot)
            + Math.max(0, n - 1) * (h * root.kGap)
            + 2 * (h * root.kPad)
    }

    // Centres a body horizontally within the window's own width (the
    // window IS screen.width wide; body x/y are window-local coordinates).
    //
    // ROUND ONCE, THEN DERIVE -- but DERIVE x WITHOUT A SECOND ROUND. w/h
    // are rounded to device pixels first; x is computed from that
    // ALREADY-ROUNDED w so the rendered right edge (x + w) stays exactly
    // screen.width - x (the original centering-drift bug this comment used
    // to describe). But x itself must NOT then be rounded a second time:
    // measured directly (analyze_pill.py, wf-recorder capture of a live
    // hover/dashboard spring) -- (screen.width - rw) flips parity on
    // essentially every frame as rw sweeps through consecutive integers
    // during a spring, so Math.round((screen.width - rw) / 2) alternates
    // between floor and ceil EVERY FRAME, i.e. the body's own centre
    // literally oscillates by 0.5px at frame rate for the whole morph, not
    // just settling once. The blob shader antialiases that sub-pixel
    // wobble away invisibly (it's a smooth SDF), but every content Item
    // anchored to this body's centre (island/Island.qml's per-state
    // content, `anchors.horizontalCenter: parent.horizontalCenter` off
    // body0Tracker) inherits it, and QML's default text rendering snaps
    // glyph positions to whole device pixels -- turning that invisible
    // 0.5px analog wobble into a visible 1px alternating jump on the
    // clock/icons every single frame the pill is springing. This is the
    // "clock and icons shake while the pill scales, but the pill body
    // itself looks smooth" the owner reported. Leaving x as the exact
    // float (screen.width - rw) / 2 makes x + w/2 == screen.width / 2
    // EXACTLY on every frame regardless of rw's parity -- no oscillation.
    // The shader and Item positioning both already accept fractional
    // floats; only the width needed device-pixel rounding for a crisp
    // fill edge.
    function centered(w, h, r, screen) {
        const rw = Math.round(w)
        const rh = Math.round(h)
        return { x: (screen.width - rw) / 2, y: 0, w: rw, h: rh, r: r }
    }

    /**
     * The tallest body height any state can produce for `screen` -- used to
     * size the ONE fixed, never-resized PanelWindow per screen (spec
     * section 1: "Height = the tallest state").
     */
    function maxHeight(screen) {
        const states = ["rest", "hover", "media", "osd", "notification",
            "dashboard", "subpage", "settings"]
        const ctx = { wifiOpen: true, bluetoothOpen: true, audioOpen: false }
        let m = 0
        for (const s of states) {
            const t = root.targets(s, screen, ctx)
            for (const b of t.bodies)
                if (b.h > m) m = b.h
        }
        return Math.ceil(m)
    }

    /**
     * `targets(state, screen, ctx)` -> { bodies: [4 rects], neckK: [k12, k13] }
     * ctx: { wifiOpen, bluetoothOpen, audioOpen, notes/todo/pet flags... }
     * (subpage/settings ignore ctx beyond sizing; content is phase B/C/D's).
     */
    function targets(state, screen, ctx) {
        ctx = ctx || {}
        const u = root.unit(screen)
        const bodies = [root.emptyBody(), root.emptyBody(), root.emptyBody(), root.emptyBody()]

        // ---- pill (body 0) ----------------------------------------------
        let pillW, pillH
        switch (state) {
        case "rest":
            pillW = 2.36 * u; pillH = 0.64 * u
            break
        case "hover":
            pillW = 10.68 * u; pillH = 1.23 * u
            break
        case "media":
            pillW = 10.68 * u; pillH = 2.2 * u
            break
        case "osd":
            pillW = 8.18 * u; pillH = 1.64 * u
            break
        case "notification":
            pillW = 10.68 * u; pillH = 1.6 * u
            break
        case "dashboard":
        case "expanded":
            // panels/DashboardSlim.qml's own dashWidth/dashHeight formula
            // (screen-derived, not a fixed Config pixel literal): width
            // min(18u, sw-2u), height <= 9u. island/IslandController.qml's
            // dashboardTargetWidth/Height compute the SAME formula from the
            // real screen and are what Island.qml actually feeds body 0 via
            // ctx.pillWidth/pillHeight -- this case is only the fallback
            // BlobLayout.maxHeight()'s sweep and test-blob-layout.qml use.
            pillW = Math.min(18 * u, screen.width - 2 * u)
            pillH = Math.min(9 * u, screen.height)
            break
        case "subpage":
            pillW = Math.min(16 * u, screen.width - 2 * u)
            pillH = Math.min(10 * u, screen.height * 0.7)
            break
        case "settings":
            // Placeholder slot only -- settings is a standalone floating
            // window per the spec (section 5), not a blob body. Sized the
            // same as "dashboard" so BlobLayout still returns a sane,
            // in-bounds body if something targets this state before that
            // lands.
            pillW = Math.min(18 * u, screen.width - 2 * u)
            pillH = Math.min(9 * u, screen.height)
            break
        default:
            pillW = 2.36 * u; pillH = 0.64 * u
        }
        // Real callers (island/Island.qml) pass the ACTUAL current
        // IslandController.targetWidth/targetHeight here instead of relying
        // on the switch above: IslandController's own table already covers
        // every page type (notifications/wallpaper/session/settings/
        // launcher/control-center/polkit/...), not just the handful this
        // switch models, and is the real source of truth for body 0's size.
        // The switch above stays authoritative for states it DOES know
        // (used by maxHeight()'s window-sizing sweep and test-blob-layout)
        // and for any caller that doesn't pass an override.
        if (ctx.pillWidth > 0)
            pillW = ctx.pillWidth
        if (ctx.pillHeight > 0)
            pillH = ctx.pillHeight
        pillW = root.clampWidth(pillW, screen, u)
        pillH = root.clampHeight(pillH, screen, u)
        const pillR = Math.min(pillH / 2, 0.5 * u + 6)
        bodies[0] = root.centered(pillW, pillH, pillR, screen)

        // ---- satellites (bodies 1/2), left = wifi, right = bluetooth/audio
        // Height is its own content's height, capped at min(9u,
        // screen.height*0.6) -- NOT clamped to the pill's own height. A
        // satellite is a side lobe hanging off the pill (top-aligned, see
        // Island.qml), not a flat slab the same height as it: matching
        // heights made pill+satellite read as one undifferentiated
        // rectangle instead of a pill with a smaller lobe fused to it.
        const satW = root.clampWidth(6.8 * u, screen, u)
        const satMaxH = Math.max(0, Math.min(9 * u, screen.height * 0.6))
        // The right satellite may ask for more room (ctx.rightMaxH: the phone
        // satellite lists 11 rows, ~545px, more than 9u). Still capped at 60%
        // of the screen height; every other right-side body keeps satMaxH.
        const rightMaxH = ctx.rightMaxH
            ? Math.max(0, Math.min(ctx.rightMaxH, screen.height * 0.6)) : satMaxH
        const wifiOpen = !!ctx.wifiOpen
        const rightOpen = !!ctx.bluetoothOpen || !!ctx.audioOpen
        // "joined" (default): the satellite OVERLAPS the pill by ~0.5u so
        // the neck only has to smooth a small, already-touching seam, not
        // visually conjure material across open space -- a polynomial
        // smooth-min's maximum distance reduction between two shapes is
        // k/4 at their exact midpoint (see shaders/blob.frag's smoothMin),
        // so bridging a real GAP of size g needs k on the order of 2g,
        // which for anything wider than a sliver either needs an enormous
        // k (badly distorting both shapes into one lump) or just doesn't
        // fuse at all -- measured directly with a static two-body harness:
        // a 150px gap with k=150 (1x the gap) rendered as two fully
        // separate shapes; only overlap + a modest k actually produced a
        // visible liquid neck. "separate" keeps a real gap and k=0, so the
        // two shapes read as unambiguously distinct.
        const joinedGap = ctx.satelliteJoin !== "separate"
        const satGap = joinedGap ? -0.5 * u : 0.5 * u

        // Top-aligned with the pill (y=0, same as bodies[0].y) -- a side
        // lobe hangs off the TOP of the pill it's fused to, not centred on
        // it, so a short satellite still visibly reads as a lobe rather
        // than a smaller rectangle floating in the middle of a taller one.
        if (wifiOpen && satW > 0 && satMaxH > 0) {
            const h = Math.max(0, Math.min(ctx.wifiContentHeight || satMaxH, satMaxH))
            const x = Math.max(0, Math.min(screen.width - satW, bodies[0].x - satW - satGap))
            bodies[1] = { x: Math.round(x), y: 0, w: Math.round(satW), h: Math.round(h), r: Math.min(h / 2, 0.5 * u) }
        }
        if (rightOpen && satW > 0 && rightMaxH > 0) {
            const h = Math.max(0, Math.min(ctx.rightContentHeight || rightMaxH, rightMaxH))
            const x = Math.max(0, Math.min(screen.width - satW, bodies[0].x + bodies[0].w + satGap))
            bodies[2] = { x: Math.round(x), y: 0, w: Math.round(satW), h: Math.round(h), r: Math.min(h / 2, 0.5 * u) }
        }

        // ---- neck factors: how strongly each satellite fuses to the pill.
        // "joined" (default, satGap above already overlaps by 0.5u) uses a
        // k of ~1.2u -- big enough, relative to the satellite's own ~6u
        // scale, to round the overlap seam into a visible liquid waist
        // (verified with the static two-body harness: 30px overlap + k=60
        // at this same ~unit=44 scale produced a clean single fused shape
        // with a visible pinch, not two touching rectangles nor one
        // undifferentiated blob). "separate" (satGap above is a real,
        // positive gap) uses k=0 -- a hard union that only matters if the
        // gap were ever negative, which it isn't in "separate" mode.
        const joined = ctx.satelliteJoin !== "separate"
        let neckK = [joined ? 1.2 * u : 0, joined ? 1.2 * u : 0]
        let inkGap = [0, 0]

        // ---- ink droplet override (Config.appearance.ink) ----------------
        // Replaces the satellite rects and neck factors with the detach
        // geometry above. ctx.wifiDetach / ctx.rightDetach are the live
        // progress values; when omitted they fall back to fully open/closed.
        if (ctx.inkDetach) {
            const pillL = bodies[0].x
            const pillR = bodies[0].x + bodies[0].w
            const pW = ctx.wifiDetach !== undefined ? ctx.wifiDetach : (wifiOpen ? 1 : 0)
            const pR = ctx.rightDetach !== undefined ? ctx.rightDetach : (rightOpen ? 1 : 0)
            const hW = Math.max(0, Math.min(ctx.wifiContentHeight || satMaxH, satMaxH))
            const hR = Math.max(0, Math.min(ctx.rightContentHeight || rightMaxH, rightMaxH))
            const L = root.inkSatellite(-1, pW, pillL, satW, hW, u, screen)
            const R = root.inkSatellite(1, pR, pillR, satW, hR, u, screen)
            bodies[1] = L.body
            bodies[2] = R.body
            neckK = [joined ? L.neck : 0, joined ? R.neck : 0]
            inkGap = [L.gap, R.gap]
        }

        return { bodies: bodies, neckK: neckK, unit: u, inkGap: inkGap }
    }
}
