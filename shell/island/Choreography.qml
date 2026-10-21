import QtQuick
import "../core"

/**
 * Choreography -- the ONE timing source for ink island transitions.
 *
 * Everything that moves with the body (content reveal, content fade-out,
 * shared elements, the rounded clip, the close hold) is derived from:
 *   p      the body's morph progress 0..1, projected from the LIVE body
 *          w/h between the size at the moment of the state change and the
 *          current target. No timer: it is a pure function of bodyW/bodyH.
 *   outMs  milliseconds since the state change, from the shared Motion
 *          clock (Motion.now), used only for the 120ms fade-out.
 * A small heartbeat MotionValue keeps Motion ticking for ~0.6s after every
 * change even if the body size does not move. Once p reaches 1 and the
 * fade-out has finished, `animating` goes false, nothing here reads
 * Motion.now any more and the layer costs nothing at rest.
 *
 * Frame-level reasoning is in island/SharedElements.qml.
 */
QtObject {
    id: root

    property string key: ""
    property real bodyW: 0
    property real bodyH: 0
    property real targetW: 0
    property real targetH: 0

    readonly property bool ink: Config.appearance.ink
    readonly property bool reduced: Motion.reduceMotion
    // Full choreography. Reduced motion (or ink off) falls back to a plain
    // crossfade / the legacy behaviour.
    readonly property bool active: ink && !reduced
    readonly property real scaleMs: Math.max(0.25, Config.appearance.motionScale)
    readonly property real outDur: 120 * scaleMs
    readonly property real holdMs: outDur * 0.75

    // Fires before any state changes (snapshot time) and after the new
    // state is installed (retarget time).
    signal aboutToChange()
    signal transitioned()

    readonly property var hosts: ["dormant", "hover", "expanded", "osd", "media", "switcher", "notification", "call", "callActive", "phoneMessage", "airplayPin", "mirroring", "camera"]
    function hostOf(k: string): string { return k === "dashboard" ? "expanded" : k }

    property string curKey: ""
    property var _snap: ({})
    property bool _hostCarried: true
    property bool animating: false
    property bool _started: true
    property bool _latched: true
    property bool _hold: false
    property bool _oldBig: false
    property real _sw: 0
    property real _sh: 0
    property real _t0: 0
    property bool _beat: false

    property MotionValue _hb: MotionValue {
        unit: "ratio"
        zeta: 1.0
        omega: Motion.presetSmooth().omega / root.scaleMs
    }

    // ---- p ------------------------------------------------------------
    readonly property real _calc: {
        const dx = root.targetW - root._sw
        const dy = root.targetH - root._sh
        const d2 = dx * dx + dy * dy
        if (d2 < 4) return 1
        const v = ((root.bodyW - root._sw) * dx + (root.bodyH - root._sh) * dy) / d2
        return Math.max(0, Math.min(1, v))
    }
    on_CalcChanged: if (_started && !_latched && _calc >= 0.999) _latched = true
    readonly property real p: _started ? (_latched ? 1 : _calc) : 0

    readonly property real outMs: animating ? Math.max(0, (Motion.now - _t0) * 1000) : 1e9

    readonly property bool _done: animating && _started && p >= 1 && outMs >= outDur
    on_DoneChanged: if (_done) animating = false

    readonly property bool clipActive: active && animating

    // While the outgoing big page fades, the body holds still, so the
    // content is gone before the slab has shrunk.
    readonly property bool holding: animating && (!_started || (_hold && outMs < holdMs))
    readonly property real bodyTargetW: active && holding ? _sw : targetW
    readonly property real bodyTargetH: active && holding ? _sh : targetH

    function _ss(a: real, b: real, x: real): real {
        const t = Math.max(0, Math.min(1, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }
    // Incoming reveal: smoothstep(0.55, 0.9, p); the rest state 0.6..0.95.
    readonly property real enterT: hostOf(curKey) === "dormant"
        ? _ss(0.6, 0.95, p) : _ss(0.55, 0.9, p)
    // Outgoing fade, eased out over outDur.
    readonly property real leaveFade: {
        const t = Math.max(0, Math.min(1, outMs / outDur))
        return 1 - (1 - t) * (1 - t)
    }

    function opacityFor(host: string): real {
        const cur = hostOf(curKey)
        if (reduced || !ink) return host === cur ? 1 : 0
        if (host === cur) return _hostCarried ? 1 : enterT
        const s = _snap[host] ?? 0
        return s <= 0 ? 0 : s * (1 - leaveFade)
    }
    function liftFor(host: string): real {
        return active && host === hostOf(curKey) && !_hostCarried ? 6 * (1 - enterT) : 0
    }
    function scaleFor(host: string): real {
        return active && host !== hostOf(curKey) ? 1 - 0.02 * leaveFade : 1
    }

    onKeyChanged: {
        if (curKey === "" || key === curKey) { curKey = key; return }
        root.aboutToChange()
        const snaps = {}
        for (const h of hosts) snaps[h] = opacityFor(h)
        const prevHost = hostOf(curKey)
        if (active) {
            _snap = snaps
            _sw = bodyW
            _sh = bodyH
            _t0 = Motion.now
            _oldBig = prevHost === "expanded" || prevHost === "media"
            _hold = false
            _latched = false
            _started = false
            animating = true
        }
        _hostCarried = hostOf(key) === prevHost
        curKey = key
        if (active) {
            _beat = !_beat
            _hb.target = _beat ? 1 : 0
            _hb.kick()
            Qt.callLater(root._begin)
        }
        root.transitioned()
    }

    // Deferred one tick so targetW/H have settled for the new state.
    function _begin(): void {
        _hold = _oldBig && targetW * targetH < _sw * _sh * 0.9
        if (_calc >= 0.999) _latched = true
        _started = true
    }
}
