pragma Singleton
import QtQuick
import Quickshell.Hyprland
import Quickshell.Io
import "."
import "../core"
import "../core/oklch.js" as K

/**
 * AdaptiveColor -- every computed colour of the glass redesign
 * (docs/superpowers/specs/2026-10-06-glass-redesign-design.md, Phase 1).
 *
 * The glass shows whatever is behind it and the wallpaper changes, so no
 * accent/fill/text colour is hand-picked. Inputs:
 *   accent   -- the matugen primary of the current wallpaper (Theme.primary)
 *   backdrop -- what is actually behind the island's panels: the focused
 *               monitor's top-centre region, grabbed with grim and averaged
 *               by ImageMagick while every island is at rest (never while a
 *               panel is open, or it would sample itself), on window/
 *               workspace changes and every few seconds (on battery: on
 *               layout changes only -- no periodic poll, no per-focus-change
 *               sample -- and never while locked or under a fullscreen
 *               window, when no island is on screen). Before the first
 *               screen sample, the wallpaper still's same band stands in,
 *               then Theme.surface.
 *               Hyprland's blur lowers contrast (decoration.blur.contrast
 *               0.74), so colours are computed against `seen`, the backdrop
 *               pulled toward mid-grey by the same amount.
 * Outputs (core/oklch.js does the maths):
 *   activeFill / activeFillText -- an "on" toggle: light, brighter-than-backdrop
 *                                shade of the accent hue, and its icon colour
 *   glassText                 -- text straight on glass
 *   glassTint                 -- the near-clear tint the glass is painted with
 *
 * overrideAccent/overrideBackdrop let tests and render harnesses pin inputs.
 */
QtObject {
    id: root

    property color overrideAccent: "transparent"
    property color overrideBackdrop: "transparent"

    property color sampledBackdrop: "transparent"   // wallpaper still
    property color screenBackdrop: "transparent"    // live screen region

    readonly property color accent: overrideAccent.a > 0 ? overrideAccent : Theme.primary
    readonly property color backdrop: overrideBackdrop.a > 0 ? overrideBackdrop
        : screenBackdrop.a > 0 ? screenBackdrop
        : (sampledBackdrop.a > 0 ? sampledBackdrop : Theme.surface)
    readonly property real blurContrast: 0.74
    readonly property color seen: Qt.rgba(0.5 + (backdrop.r - 0.5) * blurContrast,
                                          0.5 + (backdrop.g - 0.5) * blurContrast,
                                          0.5 + (backdrop.b - 0.5) * blurContrast, 1)

    function _c(o) { return Qt.rgba(o.r, o.g, o.b, 1); }

    readonly property color activeFill: _c(K.activeFill(K.fromColor(accent), K.fromColor(seen)))
    readonly property color activeFillText: _c(K.onFill(K.fromColor(activeFill)))
    readonly property color glassText: _c(K.glassText(K.fromColor(seen)))
    // Secondary text: same family at reduced alpha, never a second hue.
    readonly property color glassTextDim: Qt.rgba(glassText.r, glassText.g, glassText.b, 0.62)
    readonly property color glassTint: _c(K.glassTint(K.fromColor(seen), K.fromColor(accent)))

    // An "on" fill for an arbitrary backdrop colour (e.g. album-art glow).
    function fillFor(backdropColor) {
        return _c(K.activeFill(K.fromColor(accent), K.fromColor(backdropColor)));
    }
    function textOn(fillColor) {
        return _c(K.onFill(K.fromColor(fillColor)));
    }

    // ---- Backdrop sampling ----
    readonly property string _still: WallpaperService.currentStill
    on_StillChanged: _sampleTimer.restart()

    property Timer _sampleTimer: Timer {
        interval: 300
        onTriggered: {
            if (!root._still) return;
            root._sampler.command = ["magick", root._still, "-resize", "32x18!",
                "-crop", "12x4+10+0", "+repage", "-scale", "1x1!",
                "-format", "%[fx:r] %[fx:g] %[fx:b]", "info:"];
            root._sampler.running = true;
        }
    }

    property Process _sampler: Process {
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const v = text.trim().split(/\s+/).map(Number);
                if (v.length === 3 && v.every(n => isFinite(n)))
                    root.sampledBackdrop = Qt.rgba(v[0], v[1], v[2], 1);
            }
        }
    }

    // ---- Live screen sampling ----
    // Islands report while a panel is open (setBusy) so sampling pauses.
    property var _busy: ({})
    readonly property bool _anyBusy: Object.keys(_busy).some(k => _busy[k])
    function setBusy(key, busy) {
        const next = Object.assign({}, _busy);
        next[key] = busy;
        _busy = next;
        if (!busy) _screenDebounce.restart();
    }

    // No island is on screen to tint while the session is locked or the
    // focused workspace is fullscreen; the unlock / un-fullscreen events
    // trigger a fresh sample.
    readonly property bool _nothingShown:
        !!(LockService.lockScreen && LockService.lockScreen.locked)
        || !!(Hyprland.focusedMonitor?.activeWorkspace?.hasFullscreen)
    on_NothingShownChanged: if (!_nothingShown) _screenDebounce.restart()
    readonly property bool _lowPower: BatteryService.onBattery
    // Laptop profile (a battery is present): event-driven on AC too, plus a
    // slow safety tick. Desktops keep the 4 s poll.
    readonly property bool _laptop: BatteryService.available

    // Laptop profile: at most one grab per 5 s. A sample requested sooner is
    // deferred (not dropped) so the final state is always sampled.
    property double _lastSampleMs: 0
    readonly property int _minGapMs: 5000
    property Timer _deferred: Timer {
        repeat: false
        onTriggered: root.sampleScreen()
    }

    function sampleScreen() {
        if (_anyBusy || _nothingShown || _screenSampler.running) return;
        if (_laptop) {
            const wait = _minGapMs - (Date.now() - _lastSampleMs);
            if (wait > 0) {
                _deferred.interval = wait;
                _deferred.restart();
                return;
            }
        }
        _lastSampleMs = Date.now();
        const m = Hyprland.focusedMonitor?.lastIpcObject;
        if (!m || !m.width) return;
        const scale = m.scale || 1;
        const w = Math.round(m.width / scale), h = Math.round(m.height / scale);
        // The band the dashboard/control-centre panels cover.
        const rw = Math.min(760, w), rh = 300;
        const geom = `${m.x + Math.round((w - rw) / 2)},${m.y + 60} ${rw}x${rh}`;
        _screenSampler.command = ["sh", "-c",
            'grim -g "$1" -t ppm - 2>/dev/null | magick - -resize 1x1! -format "%[fx:r] %[fx:g] %[fx:b]" info:',
            "sh", geom];
        _screenSampler.running = true;
    }

    property Process _screenSampler: Process {
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const v = text.trim().split(/\s+/).map(Number);
                if (v.length === 3 && v.every(n => isFinite(n)) && !root._anyBusy)
                    root.screenBackdrop = Qt.rgba(v[0], v[1], v[2], 1);
            }
        }
    }

    // Each sample is a grim screen grab plus an ImageMagick process. On
    // battery the poll stops; on a laptop on AC it slows to a 30 s safety tick.
    // Laptops use a longer debounce (coalesces a burst of layout events into
    // one grab).
    property Timer _screenDebounce: Timer {
        interval: (root._lowPower || root._laptop) ? 1000 : 250
        onTriggered: root.sampleScreen()
    }
    property Timer _screenPeriodic: Timer {
        interval: root._laptop ? 30000 : 4000
        running: !root._lowPower && !root._nothingShown
        repeat: true
        onTriggered: root.sampleScreen()
    }
    property string _lastFocusAddr: ""
    property Connections _hypr: Connections {
        target: Hyprland
        function onRawEvent(event): void {
            // activewindowv2 also fires on every title change (terminal
            // spinners); on laptops only a focus move to a different window
            // address counts. Desktops keep the old behaviour.
            if (event.name === "activewindowv2" && root._laptop) {
                if (event.data === root._lastFocusAddr)
                    return;
                root._lastFocusAddr = event.data;
                if (root._lowPower)
                    return;
            }
            if (["activewindowv2", "workspacev2", "focusedmonv2", "openwindow",
                 "closewindow", "fullscreen", "changefloatingmode"].indexOf(event.name) !== -1)
                root._screenDebounce.restart();
        }
    }

    Component.onCompleted: {
        _sampleTimer.start();
        _screenDebounce.start();
    }
}
