// Mac (Tahoe) presentation switch: the uiStyle default, the `style` IPC
// target, the persisted setting, and the routing guards in
// island/IslandController.qml. Notifications, the notification centre, the
// launcher, the control centre (the "overview" page, from controlCenterToggle
// and the control-center IPC) and a ringing call must go to mac while uiStyle
// is "mac" and back to the pill otherwise. An answered call (callActive) stays
// in the pill.
//
// The real SettingsStore singleton is used. Run with XDG_STATE_HOME pointed
// at a scratch dir so the owner's settings.json is never touched. The
// original stored value is restored as the last step. phonectl is never
// spawned: PhoneService.runOverride captures each verb.
import QtQuick
import Quickshell
import "core"
import "island"
import "services"
import "mac"
import "mac/MacFormat.js" as Format

ShellRoot {
    id: root
    property var log: []
    property var macReqs: []
    property var originalStyle: undefined
    property var originalScreen: undefined
    property var originalScale: undefined
    property string lastVerb: ""
    property var pendingCb: null

    function ok(name, cond, detail) {
        log.push((cond ? "PASS  " : "FAIL  ") + name + (detail ? "   " + detail : ""))
    }
    function feed(obj) { PhoneService.handleLine(JSON.stringify(Object.assign({ v: 1 }, obj))) }
    function fakeRun(args, cb) { root.lastVerb = args[0]; root.pendingCb = cb }
    function settle(result) { const cb = root.pendingCb; root.pendingCb = null; cb(result) }

    function setStyle(style) {
        if (style === undefined)
            SettingsStore.removeValue("appearance", "uiStyle")
        else
            SettingsStore.setValue("appearance", "uiStyle", style)
    }
    function lastReq() { return root.macReqs.length ? root.macReqs[root.macReqs.length - 1] : "" }

    IslandController { id: ctrl }

    Connections {
        target: ShellActions
        function onMacSurfaceRequested(surface, action): void {
            root.macReqs = root.macReqs.concat([surface + ":" + action])
        }
        // Same mapping as island/Island.qml's control-center handlers.
        function onControlCenterToggleRequested(): void { ctrl.togglePage("overview") }
        function onControlCenterOpenRequested(): void { ctrl.openPage("overview") }
        function onControlCenterCloseRequested(): void { ctrl.closePage("overview") }
    }

    // The real mac root, so the controlCenter forwarding in MacStyleRoot is
    // exercised. Its MacControlCenter stays unmapped: nothing here opens it.
    MacStyleRoot { id: styleRoot }

    Timer {
        interval: 30; running: true; repeat: false
        onTriggered: root.run()
    }

    // Pure helpers and settings for the mac screen choice, the mac scale and
    // the avatar source priority. No layer shell is needed.
    function checkMacHelpers() {
        const origScreen = SettingsStore.value("appearance", "macScreen", undefined)
        const origScale = SettingsStore.value("appearance", "macScale", undefined)
        root.originalScreen = origScreen
        root.originalScale = origScale
        SettingsStore.removeValue("appearance", "macScreen")
        SettingsStore.removeValue("appearance", "macScale")

        // macScreen: default, validation, setter
        ok("mac_screen_default_focused", Config.appearance.macScreen === "focused", Config.appearance.macScreen)
        ok("mac_screen_valid_focused", SettingsStore.validMacScreen("focused") === true)
        ok("mac_screen_valid_output_name", SettingsStore.validMacScreen("DP-1") === true
            && SettingsStore.validMacScreen("HDMI-A-1") === true)
        ok("mac_screen_rejects_empty", SettingsStore.validMacScreen("") === false)
        ok("mac_screen_rejects_spaces_and_junk", SettingsStore.validMacScreen("DP 1") === false
            && SettingsStore.validMacScreen("../x") === false && SettingsStore.validMacScreen(42) === false)
        ok("mac_screen_setter_refuses_junk", SettingsStore.setMacScreen("bad name!") === false)
        ok("mac_screen_setter_accepts_output", SettingsStore.setMacScreen("DP-1") === true
            && Config.appearance.macScreen === "DP-1")
        SettingsStore.setValue("appearance", "macScreen", "not valid!")
        ok("mac_screen_stored_junk_falls_back", Config.appearance.macScreen === "focused", Config.appearance.macScreen)
        SettingsStore.removeValue("appearance", "macScreen")

        // screen choice (pure): focused, pinned, pinned-but-missing, fallbacks
        const screens = [{ name: "HDMI-A-1" }, { name: "DP-1" }]
        ok("screen_focused_wins", Format.macScreenFor("focused", screens, "DP-1", "HDMI-A-1").name === "DP-1")
        ok("screen_focused_uses_focus_not_primary", Format.macScreenFor("focused", screens, "HDMI-A-1", "DP-1").name === "HDMI-A-1")
        ok("screen_pinned_beats_focus", Format.macScreenFor("HDMI-A-1", screens, "DP-1", "DP-1").name === "HDMI-A-1")
        ok("screen_pinned_missing_falls_to_focus", Format.macScreenFor("eDP-1", screens, "DP-1", "HDMI-A-1").name === "DP-1")
        ok("screen_no_focus_uses_primary", Format.macScreenFor("focused", screens, "", "HDMI-A-1").name === "HDMI-A-1")
        ok("screen_nothing_known_uses_first", Format.macScreenFor("focused", screens, "", "").name === "HDMI-A-1")
        ok("screen_no_screens_is_null", Format.macScreenFor("focused", [], "DP-1", "DP-1") === null)
        ok("screen_choose_returns_or_null", (function () {
            const picked = MacScreen.choose()
            return picked === null || (typeof picked === "object" && typeof picked.name === "string")
        })())

        // macScale: default 0.85, override clamped 0.7-1.6
        ok("mac_scale_default_085", Format.macScaleFor(0, 1920) === 0.85, Format.macScaleFor(0, 1920))
        ok("mac_scale_default_ignores_width", Format.macScaleFor(0, 3840) === 0.85)
        ok("mac_scale_override", Format.macScaleFor(1.1, 1920) === 1.1)
        ok("mac_scale_clamp_low", Format.macScaleFor(0.3, 1920) === 0.7)
        ok("mac_scale_clamp_high", Format.macScaleFor(9, 1920) === 1.6)
        ok("mac_scale_override_wins", Format.macScaleFor(1.2, 1920) === 1.2)
        ok("mac_scale_override_clamped", Format.macScaleFor(3, 1920) === 1.6 && Format.macScaleFor(0.5, 1920) === 0.7)
        ok("mac_scale_live_in_range", Config.appearance.macScale >= 0.7 && Config.appearance.macScale <= 1.6,
            Config.appearance.macScale)
        ok("mac_tokens_s_applies_mac_scale", Math.abs(MacTokens.s(10)
            - 10 * DisplayScale.primary * Config.appearance.macScale) < 1e-9)
        SettingsStore.setMacScale(9)
        ok("mac_scale_setter_clamps", SettingsStore.value("appearance", "macScale", 0) === 1.6)
        SettingsStore.removeValue("appearance", "macScale")

        // MacAvatar source priority: app icon, stable image, letter
        ok("avatar_app_icon_first", Format.avatarSource("/usr/share/icons/app.png", "/tmp/img.png") === "/usr/share/icons/app.png")
        ok("avatar_qsimage_never_bound", Format.avatarSource("", "image://qsimage/119/1") === "")
        ok("avatar_qsimage_not_bound_with_icon", Format.avatarSource("/icons/a.png", "image://qsimage/119/1") === "/icons/a.png")
        ok("avatar_file_image_used_without_icon", Format.avatarSource("", "file:///tmp/a.png") === "file:///tmp/a.png")
        ok("avatar_abs_path_image_used", Format.avatarSource("", "/tmp/a.png") === "/tmp/a.png")
        ok("avatar_http_image_refused", Format.avatarSource("", "https://h.example/a.png") === "")
        ok("avatar_letter_when_nothing", Format.avatarSource("", "") === "" && Format.avatarSource("", undefined) === "")
        ok("avatar_unknown_scheme_refused", Format.avatarSource("", "data:image/png;base64,xx") === "")

        restoreValue("macScreen", origScreen)
        restoreValue("macScale", origScale)
    }

    // Hot-corner / backdrop tokens and the requestOn() toggle. Offscreen the
    // layer windows are never built, so only the Item state is driven.
    function checkNotificationCenter() {
        const nc = styleRoot.notificationCenter
        ok("nc_starts_closed", nc.open === false, nc.open)
        nc.requestOn("toggle", null)
        ok("nc_requestOn_toggle_opens", nc.open === true, nc.open)
        nc.requestOn("toggle", null)
        ok("nc_requestOn_toggle_closes", nc.open === false, nc.open)
        ok("nc_backdrop_width_positive", MacTokens.ncBackdropWidth > 0, MacTokens.ncBackdropWidth)
        ok("nc_backdrop_alpha_in_range", MacTokens.ncBackdropMaxAlpha > 0 && MacTokens.ncBackdropMaxAlpha < 1,
            MacTokens.ncBackdropMaxAlpha)
    }

    function run() {
        root.originalStyle = SettingsStore.value("appearance", "uiStyle", undefined)
        checkMacHelpers()
        checkNotificationCenter()
        PhoneService.runOverride = root.fakeRun
        feed({ type: "status", connected: true, device: { name: "iPhone" } })
        PhoneAttention.lockedOverride = false
        PhoneAttention.idleOverride = true

        // ---- defaults ----------------------------------------------------
        setStyle(undefined)
        ok("default_ui_style_is_pill", Config.appearance.uiStyle === "pill", Config.appearance.uiStyle)
        ok("default_mac_style_false", Config.appearance.macStyle === false)
        ok("default_mac_live_activities_true", Config.appearance.macLiveActivities === true)

        // ---- validation: unknown values fall back to pill ------------------
        ok("set_rejects_unknown", SettingsStore.setUiStyle("chrome") === false
            && Config.appearance.uiStyle === "pill")
        SettingsStore.setValue("appearance", "uiStyle", "bogus")
        ok("unknown_stored_value_falls_back_to_pill", Config.appearance.uiStyle === "pill",
            Config.appearance.uiStyle)
        setStyle(undefined)

        // ---- IPC: set / get / toggle --------------------------------------
        ok("ipc_set_mac", ShellActions.styleIpc.set("mac") === "STYLE_SET_SUCCESS"
            && Config.appearance.uiStyle === "mac")
        ok("ipc_get_reports_mac", ShellActions.styleIpc.get() === "mac", ShellActions.styleIpc.get())
        ok("ipc_set_invalid", ShellActions.styleIpc.set("windows") === "STYLE_SET_INVALID"
            && Config.appearance.uiStyle === "mac")
        ok("ipc_set_pill", ShellActions.styleIpc.set("pill") === "STYLE_SET_SUCCESS"
            && ShellActions.styleIpc.get() === "pill")
        ok("ipc_toggle_to_mac", ShellActions.styleIpc.toggle() === "STYLE_TOGGLE_SUCCESS"
            && Config.appearance.macStyle === true)
        ok("ipc_toggle_back_to_pill", ShellActions.styleIpc.toggle() === "STYLE_TOGGLE_SUCCESS"
            && Config.appearance.uiStyle === "pill")
        ok("persisted_value_round_trips", (SettingsStore.setUiStyle("mac"),
            SettingsStore.value("appearance", "uiStyle", "") === "mac"))
        setStyle(undefined)

        // ---- routing: mac style -------------------------------------------
        setStyle("mac")
        root.macReqs = []
        ctrl.togglePage("launcher")
        ok("mac_launcher_toggle_routed", root.lastReq() === "launcher:toggle", root.lastReq())
        ok("mac_launcher_not_in_pill", ctrl.expandedActive === false && ctrl.expandedPage !== "launcher")
        ctrl.openPage("notifications")
        ok("mac_nc_open_routed", root.lastReq() === "notifications:open", root.lastReq())
        ok("mac_nc_not_in_pill", ctrl.expandedActive === false)
        ctrl.closePage("launcher")
        ok("mac_launcher_close_routed", root.lastReq() === "launcher:close", root.lastReq())

        // ---- control centre (overview) ------------------------------------
        ctrl.togglePage("overview")
        ok("mac_cc_toggle_routed", root.lastReq() === "controlCenter:toggle", root.lastReq())
        ok("mac_cc_not_in_pill", ctrl.expandedActive === false, ctrl.expandedPage)
        ctrl.openPage("overview")
        ok("mac_cc_open_routed", root.lastReq() === "controlCenter:open", root.lastReq())
        ctrl.closePage("overview")
        ok("mac_cc_close_routed", root.lastReq() === "controlCenter:close", root.lastReq())
        ShellActions.controlCenterIpc.toggle()
        ok("mac_cc_ipc_toggle_routed", root.lastReq() === "controlCenter:toggle", root.lastReq())
        ShellActions.controlCenterIpc.open()
        ok("mac_cc_ipc_open_routed", root.lastReq() === "controlCenter:open", root.lastReq())
        ShellActions.controlCenterIpc.close()
        ok("mac_cc_ipc_close_routed", root.lastReq() === "controlCenter:close", root.lastReq())
        ok("mac_cc_ipc_not_in_pill", ctrl.expandedActive === false, ctrl.expandedPage)
        // Forwarded on to the MacControlCenter surface (MacStyleRoot).
        ShellActions.macSurfaceRequested("controlCenter", "close")
        ok("mac_cc_forwarded_to_surface", styleRoot.controlCenter.lastAction === "close",
            styleRoot.controlCenter.lastAction)
        ok("mac_cc_surface_stays_closed", styleRoot.controlCenter.open === false)

        ctrl.showNotification(false)
        ok("mac_toast_not_in_pill", ctrl.transientState !== "notification"
            && ctrl.visualState !== ctrl.notification, ctrl.transientState)

        feed({ type: "call", id: "m1", state: "incoming", number: "+44 9" })
        ok("mac_ringing_call_not_in_pill", ctrl.visualState !== "call" && ctrl.visualState !== "callActive",
            ctrl.visualState)
        feed({ type: "call", id: "m1", state: "ended" })
        ctrl.clearTransient()

        // A call answered in mac style stays in the pill (live activity).
        feed({ type: "call", id: "m2", state: "incoming", number: "+44 8" })
        PhoneService.answer()
        ok("mac_answered_call_stays_in_pill", ctrl.visualState === "callActive", ctrl.visualState)
        settle({ v: 1, ok: true })
        feed({ type: "call", id: "m2", state: "ended" })
        ctrl.clearTransient()

        // ---- routing: pill style (unchanged) -------------------------------
        setStyle("pill")
        const before = root.macReqs.length
        ctrl.togglePage("launcher")
        ok("pill_launcher_opens_pill_page", ctrl.expandedActive === true && ctrl.expandedPage === "launcher",
            ctrl.expandedPage)
        ok("pill_launcher_not_routed", root.macReqs.length === before)
        ctrl.dismiss(true)
        ctrl.togglePage("overview")
        ok("pill_overview_opens_pill_page", ctrl.expandedActive === true && ctrl.expandedPage === "overview",
            ctrl.expandedPage)
        ok("pill_overview_not_routed", root.macReqs.length === before)
        ctrl.dismiss(true)
        ctrl.showNotification(false)
        ok("pill_toast_presents", ctrl.transientState === "notification", ctrl.transientState)
        ctrl.clearTransient()
        feed({ type: "call", id: "p1", state: "incoming", number: "+44 7" })
        ok("pill_ringing_call_card", ctrl.visualState === "call", ctrl.visualState)
        feed({ type: "call", id: "p1", state: "ended" })
        ctrl.clearTransient()
        ok("pill_routes_nothing", root.macReqs.length === before)

        // ---- macLiveActivities (spec 3.7): the pill hides only in mac with live activities off
        const liveOriginal = SettingsStore.value("appearance", "macLiveActivities", undefined)
        setStyle("mac")
        SettingsStore.setMacLiveActivities(false)
        ok("mac_no_live_hides_pill", Config.appearance.pillHidden === true)
        SettingsStore.setMacLiveActivities(true)
        ok("mac_live_keeps_pill", Config.appearance.pillHidden === false)
        SettingsStore.setMacLiveActivities(false)
        setStyle("pill")
        ok("pill_style_never_hides_pill", Config.appearance.pillHidden === false)
        restoreValue("macLiveActivities", liveOriginal)
        ok("live_activities_setting_restored", SettingsStore.value("appearance", "macLiveActivities", undefined) === liveOriginal)

        // ---- crossfade (spec 2): 220 ms ramp, instant under reduced motion ----
        // Reduced motion first (synchronous): no ramp, unmounted at once.
        root.reducedOriginal = SettingsStore.value("appearance", "reducedMotion", undefined)
        SettingsStore.setValue("appearance", "reducedMotion", true)
        setStyle("mac")
        ok("reduced_motion_mac_instant", MacPresence.level === 1 && MacPresence.mounted === true, MacPresence.level)
        setStyle("pill")
        ok("reduced_motion_pill_instant", MacPresence.level === 0 && MacPresence.mounted === false, MacPresence.level)
        restoreValue("reducedMotion", root.reducedOriginal)

        // Full motion (asynchronous, steps in fadeNext()).
        root.fadeStep = 1
        setStyle("mac")
        ok("crossfade_mounts_at_once", MacPresence.mounted === true)
        ok("crossfade_ramps_in", MacPresence.level < 1, MacPresence.level)
        fadeTimer.start()
    }

    property var reducedOriginal: undefined
    property int fadeStep: 0

    Timer {
        id: fadeTimer
        interval: 400
        repeat: false
        onTriggered: root.fadeNext()
    }

    function fadeNext() {
        if (root.fadeStep === 1) {
            ok("crossfade_settles_at_mac", MacPresence.level === 1, MacPresence.level)
            root.fadeStep = 2
            setStyle("pill")
            // The level animates from 1, so only the mount is checked this frame.
            ok("crossfade_mounted_through_fade_out", MacPresence.mounted === true && MacPresence.wanted === false,
                MacPresence.level)
            fadeTimer.start()
        } else {
            ok("crossfade_unmounts_after_fade", MacPresence.mounted === false && MacPresence.level === 0,
                MacPresence.level)
            restoreAndFinish()
        }
    }

    function restoreValue(key, original) {
        if (original === undefined)
            SettingsStore.removeValue("appearance", key)
        else
            SettingsStore.setValue("appearance", key, original)
    }

    function restoreAndFinish() {
        setStyle(root.originalStyle)
        restoreValue("macScreen", root.originalScreen)
        restoreValue("macScale", root.originalScale)
        ok("original_style_restored", SettingsStore.value("appearance", "uiStyle", undefined) === root.originalStyle)
        finish()
    }

    function finish() {
        for (const line of root.log) console.log(line)
        const failed = root.log.filter(l => l.indexOf("FAIL") === 0).length
        console.log("=== " + (root.log.length - failed) + "/" + root.log.length + " passed ===")
        Qt.exit(failed === 0 ? 0 : 1)
    }
}
