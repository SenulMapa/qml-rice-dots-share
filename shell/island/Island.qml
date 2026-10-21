import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import "../components"
import "../core"
import "../services"

PanelWindow {
    id: window
    // Env-gated geometry trace. Screenshot diffs cannot separate the surface's
    // GEOMETRY from its CONTENT fading (the fill is near-transparent over a
    // dark desktop), so this logs the real width/height/y, the controller's
    // visual state, the targets and the spring velocities on every change.
    // Costs nothing unless QMLRICE_TRACE_GEOMETRY=1.
    // Env-gated input trace (QMLRICE_TRACE_INPUT=1): presses reaching the island
    // and each satellite, hover enter/leave, and focus-grab clears -- the three
    // things that decide whether a click inside a satellite keeps the control
    // centre open. PointHandlers are passive and do not change delivery.
    readonly property bool inputTrace: Quickshell.env("QMLRICE_TRACE_INPUT") === "1"
    readonly property bool geometryTrace: Quickshell.env("QMLRICE_TRACE_GEOMETRY") === "1"
    // Env-gated frame-timing probe (QMLRICE_TRACE_FRAMES=1) -- see
    // components/FrameProbe.qml. Loader.active false means the probe (and its
    // FrameAnimation) is never even constructed when the gate is off.
    readonly property bool frameTrace: Quickshell.env("QMLRICE_TRACE_FRAMES") === "1"
    function traceGeometry(): void {
        console.log("GEOM " + Date.now() + " w=" + body0Tracker.width + " h=" + body0Tracker.height
            + " y=" + body0Tracker.y + " state=" + islandController.visualState
            + " tW=" + islandController.targetWidth + " tH=" + islandController.targetHeight
            + " wV=" + window.bodyW.velocity.toFixed(3)
            + " hV=" + window.bodyH.velocity.toFixed(3))
    }

    readonly property var monitor: Hyprland.monitorFor(screen)
    readonly property bool monitorEnabled:
        HyprlandService.islandEnabledFor(monitor)
    readonly property bool presentationTarget:
        HyprlandService.shouldPresentOn(monitor)
    // Whichever of the real or preview polkit controller currently has a
    // live/staged request -- see panels/PolkitPage.qml. Used to close the
    // polkit page automatically on completion/external cancellation, since
    // relying on AuthFlow's own completion signals directly would race
    // PolkitAgent.flow being reset to null in the same call (see
    // services/PolkitService.qml).
    readonly property bool polkitFlowOpen:
        PolkitService.active || PolkitPreviewService.previewing
    onPolkitFlowOpenChanged: {
        if (!polkitFlowOpen && islandController.expandedPage === "polkit")
            islandController.closePage("polkit")
    }

    IslandController {
        id: islandController
        // Preview override (services/PreviewService.qml's `lyric` IPC call)
        // widens the resting pill's lyric band the same way a real active
        // lyric would, for screenshotting without a real track playing.
        lyricsVisible: LyricsService.active
            || (PreviewService.enabled && PreviewService.lyricOverride.length > 0)
        // Workspace-fill continues to use the normal resting/auto-hide flow.
        // Only true fullscreen suppresses the lip and uses the invisible edge.
        fullscreen: HyprlandService.trueFullscreenOn(
            window.monitor?.activeWorkspace)
        mediaVisible: MediaService.hoverVisible && Config.island.hoverShowMedia
        controlCenterContentHeight: expandedContent.controlCenterContentHeight
        polkitContentHeight: expandedContent.polkitContentHeight
        dashboardContentHeight: expandedContent.dashboardContentHeight
        calendarContentHeight: expandedContent.calendarContentHeight
        // impasto's roomForPanel -- see IslandController.qml's own comment
        // on the property. This shell's island isn't hosted inside a bar
        // (no Bar.panelRoom to subtract from), so "room" is simply the
        // monitor's own width.
        roomForPanel: window.screen ? window.screen.width : 100000
        screen: window.screen
    }

    // Registers this window's Eq consumer with VisualizerService.qml's
    // visibility gate: cava has no reason to run while the dormant/hover
    // pill it feeds is parked off-screen (auto-hidden) or this monitor's
    // island is disabled/hidden entirely. See services/VisualizerService.qml.
    readonly property bool eqConsumerVisible: window.monitorEnabled
        && islandController.shouldShow && !islandController.revealOnly
    onEqConsumerVisibleChanged: VisualizerService.setWindowVisible(
        window.toString(), window.eqConsumerVisible)
    Component.onCompleted: VisualizerService.setWindowVisible(
        window.toString(), window.eqConsumerVisible)
    Component.onDestruction: VisualizerService.setWindowVisible(
        window.toString(), false)

    // Feature 2 (launcher workspace toast): fires ShellActions.launcherOpened
    // exactly on the false->true edge of "the launcher is now the active
    // expanded page" -- not on close, and not on a toggle that closed it.
    // Only the presenting monitor announces the open, matching how the
    // launcher panel itself only actually renders there.
    readonly property bool launcherPageActive:
        islandController.expandedActive && islandController.expandedPage === "launcher"
    onLauncherPageActiveChanged: {
        if (window.launcherPageActive && window.presentationTarget)
            ShellActions.launcherOpened(window.monitor)
    }

    // Arming delay: when the island is opened BY A CLICK on the pill (the
    // hover capsule's clock opening the dashboard, an icon opening its
    // card), the compositor reports this grab cleared on the same click
    // that opened it -- the pointer/keyboard still belong to whatever was
    // focused before -- so the panel was dismissed in the same frame it
    // opened. That is why the pill appeared to need a second click: the
    // first one opened and closed it. Opening via IPC or a bind never hit
    // this, since no click is in flight. Ignore a clear until the grab has
    // been active for a beat; a real click-away always arrives later.
    property bool focusGrabArmed: false

    Timer {
        id: focusGrabArming
        interval: 250
        onTriggered: window.focusGrabArmed = true
    }

    onExpandedActiveChanged: {
        window.focusGrabArmed = false
        if (islandController.expandedActive)
            focusGrabArming.restart()
        else
            focusGrabArming.stop()
    }

    readonly property bool expandedActive: islandController.expandedActive
    // While this island shows anything bigger than the resting pill, the
    // glass colour sampler must not grab the screen (it would sample our own
    // panel); see services/AdaptiveColor.qml.
    readonly property bool _coversSampleBand: islandController.expandedPresentationActive
        || islandController.logicalState === islandController.hover
    on_CoversSampleBandChanged: AdaptiveColor.setBusy(screen ? screen.name : "island", _coversSampleBand)

    HyprlandFocusGrab {
        windows: [window]
        active: islandController.expandedActive
            || islandController.visualState === islandController.phoneMessage
        onCleared: {
            if (window.inputTrace) console.log("INPUT focusGrab cleared t=" + Date.now())
            if (islandController.visualState === islandController.phoneMessage) {
                // The grab clears on the opening click; ignore that first beat.
                if (Date.now() - islandController.phoneMessageOpenedMs > 600)
                    islandController.clearTransient()
            } else if (window.focusGrabArmed)
                islandController.dismiss()
        }
    }

    IdleInhibitor {
        window: window
        enabled: IdleService.inhibited
    }

    // Per-window spring driver. Motion.qml used to be stepped ONLY by its own
    // singleton FrameAnimation, which has no window/Item ancestry -- measured
    // (test-frameswap-probe.qml, ad hoc) to NOT reliably track any specific
    // output's vsync: an unparented FrameAnimation just rides whatever ambient
    // paint activity already exists elsewhere in the process, which is why
    // the HDMI-A-1 island felt less smooth than DP-1's despite both using the
    // same spring math -- HDMI's springs were being stepped at ~60/s, not its
    // native ~120/s, so a 120Hz surface was presenting stale/duplicated
    // values roughly every other frame.
    //
    // A FrameAnimation that IS a direct child of a specific PanelWindow (this
    // one) DOES track that window's own presentation rate correctly under the
    // threaded render loop this shell already forces (shell.qml's pragma) --
    // measured HDMI-A-1 ~115-120 ticks/s and DP-1 ~57-60 ticks/s concurrently
    // once each window drives Motion.tick() itself. Motion.tick() reads its
    // own wall clock (see core/Motion.qml), so two windows calling it
    // concurrently never double-count elapsed time -- this is safe to run
    // alongside Motion's own fallback clock (headless tests, pre-window
    // startup) with no extra bookkeeping here.
    //
    // Gated on Motion.activeCount, same as Motion's own clock: a window with
    // no springs active costs a FrameAnimation that never runs, i.e. zero
    // frames requested at rest -- unchanged idle cost on the low-tier
    // machine's screen (see core/Animations.qml / services/PerformanceService.qml).
    FrameAnimation {
        id: perWindowMotionClock
        running: Motion.activeCount > 0
        onTriggered: {
            Motion.tick()
            // core/FrameProbe.qml (`frameprobe` IPC target) -- fed from
            // THIS real per-window driver, not its own singleton
            // FrameAnimation, for the same vsync-tracking reason this
            // window drives Motion.tick() itself (see this property's own
            // comment above).
            MotionFrameProbe.recordFrame(frameTime * 1000.0)
        }
    }

    Loader {
        active: window.frameTrace
        sourceComponent: FrameProbe {
            screenName: window.screen ? window.screen.name : ""
            anchorItem: body0Tracker
        }
    }


    anchors.top: true
    // A hidden surface must be hosted at the physical edge. A negative child
    // coordinate cannot reveal pixels above a PanelWindow that itself starts
    // below the configured top margin.
    margins.top: islandController.revealOnly ? 0 : Config.island.topMargin
    readonly property bool liveEditActive:
        expandedContent.settingsLivePreviewActive
    readonly property string liveEditMode: expandedContent.settingsPreviewMode
    readonly property int liveEditPreviewHeight: liveEditMode === "hover"
        ? Config.island.hoverHeight : Config.island.dormantHeight
    readonly property int liveEditOffset: liveEditActive
        ? liveEditPreviewHeight + Theme.space3 : 0
    // ONE fixed, full-width, never-resized window per screen (blob-rebuild
    // spec section 1). Width is simply the screen's own width -- the input
    // mask below already restricts clicks to the live body rects, so a
    // screen-width transparent window costs nothing extra to have around
    // it. Height is the tallest of every BlobLayout state AND the old
    // Config-literal ceiling (BlobLayout only models the blob's own simple
    // states -- rest/hover/media/osd/notification/dashboard -- not every
    // Config-sized page this island can still open, eg. launcher/settings/
    // session/insights, so the old formula stays as a floor no BlobLayout
    // state may shrink the window below).
    // controlCenterMaxContentHeight is a generous static ceiling for the
    // control centre's worst case (full tile grid + both sliders + the
    // media card expanded into its lyrics view + 3 notifications) -- only
    // used to size this window's own canvas, never the live layout.
    readonly property int controlCenterMaxContentHeight: Theme.u(20)
    implicitWidth: screen ? screen.width : 1920
    implicitHeight: Math.max(
        Config.island.expandedHeight, Config.launcher.height,
        controlCenterMaxContentHeight, Config.insights.height,
        Config.dashboard.height, Config.session.height, Config.settings.height,
        screen ? BlobLayout.maxHeight(screen) : 0)
        + liveEditOffset
    color: "transparent"
    // Config.appearance.pillHidden: mac style with macLiveActivities off hides the whole pill.
    visible: monitorEnabled && islandController.shouldShow && !Config.appearance.pillHidden
    // The input mask is the live union of the pill's tracker Item
    // (body0Tracker, following the SAME spring-driven x/y/w/h the blob
    // shape itself renders at) and both satellite trackers. A closed
    // satellite tracker has width/height 0 (see below), so combining it
    // unconditionally contributes zero area -- no separate "only while
    // visible" branch needed, same reasoning the old per-Rectangle mask
    // already relied on.
    mask: Region {
        item: islandController.revealOnly ? revealTarget : body0Tracker
        Region {
            item: wifiSatellite
            intersection: Intersection.Combine
        }
        Region {
            item: bluetoothSatellite
            intersection: Intersection.Combine
        }
    }
    exclusiveZone: monitorEnabled
            && !islandController.revealOnly
            && !(Config.island.autoHide
                && islandController.overlayWithoutReservation)
        ? Config.island.reservedSpace : 0

    WlrLayershell.namespace: "qml-rice:island"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: islandController.expandedActive
            || islandController.visualState === islandController.phoneMessage
        ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    onMonitorEnabledChanged: {
        if (!monitorEnabled)
            islandController.deactivateForMonitorPolicy()
    }

    // ---- Blob geometry: ONE shared shader shape, three springed bodies --
    // body 0 is the pill. Its w/h are MotionValues retargeted straight from
    // IslandController.targetWidth/Height (still the single source of
    // truth for every page's size -- notifications/wallpaper/session/
    // settings/launcher/control-center/polkit/overview all already go
    // through it, and BlobLayout only models the blob's own simple states).
    // x and radius are DERIVED from the springs (same as the pre-blob
    // surface derived its own x from its own width spring) rather than
    // separately sprung -- there is nothing for a second spring to smooth
    // that isn't already smooth once w/h are.
    // Preset: smooth for every state change, per the spec; bouncy
    // specifically while a notification is arriving/showing, so it reads
    // as an alert landing rather than the same measured morph as a page
    // change.
    readonly property var _bodyPreset: islandController.visualState === islandController.notification
        ? Motion.presetBouncy() : Motion.presetSmooth()
    // ink: island/Choreography.qml is the one timing source (p, fades, hold).
    readonly property string choreoKey: {
        // dismiss() sets `dismissing` BEFORE it flips logicalState, and this
        // binding re-evaluates in between: without this line that instant
        // reads as a phantom "expanded" state (expandedActive is already
        // false), which started a no-size-change transition that stranded the
        // shared art/title in an empty slab for ~1.3s on close.
        if (islandController.dismissing && islandController.transientState === "")
            return islandController.dismissTarget
        const v = islandController.visualState
        if (islandController.expandedActive && islandController.dashboardPage)
            return "dashboard"
        return ["dormant", "hover", "expanded", "media", "notification", "switcher",
            "call", "callActive", "phoneMessage", "airplayPin", "mirroring", "camera"].indexOf(v) >= 0
            ? v : "osd"
    }
    property Choreography choreography: Choreography {
        key: window.choreoKey
        bodyW: window.bodyW.value
        bodyH: window.bodyH.value
        targetW: islandController.targetWidth
        targetH: islandController.targetHeight
    }
    property MotionValue bodyW: MotionValue {
        unit: "px"
        target: window.choreography.bodyTargetW
        omega: window._bodyPreset.omega / Math.max(0.25, Config.appearance.motionScale)
        zeta: window._bodyPreset.zeta
    }
    property MotionValue bodyH: MotionValue {
        unit: "px"
        target: window.choreography.bodyTargetH
        omega: window._bodyPreset.omega / Math.max(0.25, Config.appearance.motionScale)
        zeta: window._bodyPreset.zeta
    }
    // Vertical position: unchanged from the old surfaceY (reveal-hide
    // parking / live settings preview), just renamed and now driving a
    // TRACKED body instead of a visible Rectangle directly.
    property MotionValue bodyY: MotionValue {
        unit: "px"
        zeta: 0.92
        omega: 17.4 / Math.max(0.25, Config.appearance.motionScale)
        target: window.liveEditActive ? window.liveEditOffset
            : islandController.revealOnly ? -islandController.targetHeight : 0
        immediate: islandController.immediateHiddenTransition
    }

    // Ink droplet (Config.appearance.ink): one detach progress per satellite.
    // 0 = merged into the pill edge, 1 = floats free at its resting gap,
    // slightly >1 on the bouncy overshoot. BlobLayout derives the satellite's
    // size, travel and neck from it, so the whole droplet is this one spring.
    // Bouncy (response 0.50s, damping 0.75) keeps the morph inside the
    // ~520ms family. Unit "ratio" so restDelta is 0.001, not 0.1px.
    property MotionValue wifiDetachMV: MotionValue {
        unit: "ratio"
        omega: Motion.presetBouncy().omega / Math.max(0.25, Config.appearance.motionScale)
        zeta: Motion.presetBouncy().zeta
        target: expandedContent.wifiSatelliteVisible ? 1 : 0
    }
    property MotionValue rightDetachMV: MotionValue {
        unit: "ratio"
        omega: Motion.presetBouncy().omega / Math.max(0.25, Config.appearance.motionScale)
        zeta: Motion.presetBouncy().zeta
        target: bluetoothSatellite.rightSatelliteVisible ? 1 : 0
    }

    // Pure geometry (core/BlobLayout.qml), recomputed whenever anything it
    // reads changes -- including every frame bodyW/bodyH are mid-spring, so
    // satellite offsets track the pill's LIVE size, not just its resting
    // one. wifiOpen/bluetoothOpen are forced true here regardless of the
    // real satellite visibility: this call only supplies each satellite's
    // constant width/x-offset/radius and its "fully open" height target --
    // the actual open/close ANIMATION is the satellites' own height
    // MotionValues below (0 when closed), not BlobLayout's absent-body
    // (w=h=0) contract, so the shape grows/shrinks smoothly instead of
    // popping in at full size the instant a satellite opens.
    readonly property var blobLayout: BlobLayout.targets(
        islandController.visualState, window.screen, {
            pillWidth: window.bodyW.value,
            pillHeight: window.bodyH.value,
            wifiOpen: true,
            bluetoothOpen: true,
            wifiContentHeight: wifiPanel.contentHeight,
            rightContentHeight: rightPanelLoader.item ? rightPanelLoader.item.contentHeight : 0,
            // Phone satellite: its rows need more than the 9u cap; let it take its own height.
            rightMaxH: bluetoothSatellite.phoneSatelliteVisible ? Infinity : 0,
            satelliteJoin: Config.island.satelliteJoin,
            inkDetach: Config.appearance.ink,
            wifiDetach: window.wifiDetachMV.value,
            rightDetach: window.rightDetachMV.value
        })
    readonly property real bodyRadius: window.blobLayout.bodies[0].r

    property real pillPulse: 0
    property color pillPulseColor: Theme.success
    // Glass (6 Oct 2026 redesign, superseding the 13 Sep solid fill): a
    // near-clear AdaptiveColor tint at Theme.glassAlpha -- above Hyprland's
    // ignore_alpha (0.19) so the layer rule blurs what is behind it -- with
    // the pulse tinting it as before.
    // Ink redesign (Config.appearance.ink): opaque #000, no tint, no pulse.
    readonly property color pillFillColor: {
        if (Config.appearance.ink) return Theme.ink;
        const t = Qt.tint(AdaptiveColor.glassTint, Qt.alpha(pillPulseColor, pillPulse * 0.46));
        return Qt.rgba(t.r, t.g, t.b, Theme.glassAlpha);
    }

    BlobSurface {
        id: blobSurface
        anchors.fill: parent
        fillColor: window.pillFillColor
        // Ink: no specular rim, and the 1px edge comes from the shader's
        // outline band (outlineWidth 1px, white at 0.07 alpha on black).
        // That band lies inside the SDF edge and is modulated by light
        // facing (~0.4x-1x of outline), so it is approximately, not exactly,
        // the showcase's uniform outer inkRim.
        rim: Config.appearance.ink ? 0 : 0.5
        // Ink: no lit inner outline (it read as a patchy grey arc); the edge
        // is the shader's even outer `ring` instead.
        outline: Config.appearance.ink ? 0 : 0.45
        outlineWidth: 1.4
        ring: Config.appearance.ink ? 0.09 : 0
        bodies: [
            { x: window.blobLayout.bodies[0].x, y: Math.round(window.bodyY.value),
              w: Math.round(window.bodyW.value), h: Math.round(window.bodyH.value),
              r: window.bodyRadius },
            { x: wifiSatellite.x, y: wifiSatellite.y,
              w: wifiSatellite.width, h: wifiSatellite.height, r: wifiSatellite.radius },
            { x: bluetoothSatellite.x, y: bluetoothSatellite.y,
              w: bluetoothSatellite.width, h: bluetoothSatellite.height, r: bluetoothSatellite.radius },
            { x: 0, y: 0, w: 0, h: 0, r: 0 }
        ]
        // Ink: the neck is a function of the detach progress (snaps off at
        // the gap band in BlobLayout), so it reads the geometry directly
        // instead of the bouncy neckMV spring, which would soften the snap.
        neckK: Config.appearance.ink
            ? window.blobLayout.neckK
            : [wifiSatellite.neckMV.value, bluetoothSatellite.neckMV.value]
    }

    // Invisible -- purely a body-0 tracker for input (TapHandler/
    // HoverHandler, moved off the old visible Surface Rectangle) and for
    // the mask Region below. Geometry mirrors EXACTLY what BlobSurface's
    // bodies[0] renders, so the clickable/hoverable area always matches
    // the drawn shape.
    Item {
        id: body0Tracker
        // SETTLED-SNAP (see the wrapper x: comments below in contentFocus):
        // BlobLayout.centered()'s x: (screen.width - rw) / 2 lands on a
        // half-pixel whenever rw (the rounded pill width) is odd, and every
        // wrapper below centres itself relative to THIS Item, so a
        // fractional ancestor here defeated the wrapper-level settled-snap
        // fix by itself. Round once nothing is animating; the blob shader
        // (BlobSurface above) still reads window.blobLayout.bodies[0].x
        // directly, not this property, so the drawn shape stays exactly
        // where it always was -- this only moves the (invisible) input/mask
        // tracker by at most half a device pixel at rest.
        x: Motion.activeCount > 0
            ? window.blobLayout.bodies[0].x
            : Math.round(window.blobLayout.bodies[0].x)
        y: Math.round(window.bodyY.value)
        width: Math.round(window.bodyW.value)
        height: Math.round(window.bodyH.value)
        clip: true
        onWidthChanged: if (window.geometryTrace) window.traceGeometry()
        onHeightChanged: if (window.geometryTrace) window.traceGeometry()
        onYChanged: if (window.geometryTrace) window.traceGeometry()
        PointHandler {
            enabled: window.inputTrace
            onActiveChanged: if (active) console.log("INPUT press surface t=" + Date.now())
        }

        FocusScope {
            id: contentFocus
            anchors.fill: parent
            focus: islandController.expandedActive
            Keys.onEscapePressed: {
                if (!expandedContent.closeTransientUi())
                    islandController.dismiss(true)
            }

            // Rounded clip that follows the blob's live w/h/radius. Only
            // used while a choreographed transition is in flight
            // (ClippingRectangle renders through a layer, so the content is
            // reparented under it for the duration and back at rest).
            ClippingRectangle {
                id: roundClip
                anchors.fill: parent
                radius: window.bodyRadius
                color: "transparent"
                visible: window.choreography.clipActive
            }

            Item {
                id: hostsLayer
                anchors.fill: parent
                parent: window.choreography.clipActive ? roundClip.contentItem : contentFocus

            Item {
                id: restWrapper
                anchors.top: parent.top
                // Explicit float centring, NOT anchors.horizontalCenter --
                // measured directly (debug SHAKE trace, live capture during a
                // real hover morph): Qt Quick's own anchor engine resolves
                // horizontalCenter with a parity-dependent 0.5px quirk of its
                // own (deviates from the algebraically exact parent centre by
                // exactly 0.5px whenever the LIVE, per-frame contentFocus.width
                // -- Math.round(bodyW.value), changing every frame mid-spring --
                // happens to be odd, and 0px when even), even though
                // core/BlobLayout.qml's own centred() already keeps the parent's
                // true centre exactly constant. That 0.5px anchor-engine wobble
                // is what read as "the clock and icons shake while the pill
                // scales" -- the pill body itself never used anchors here (it's
                // pure float math), only its content did. Computing x ourselves,
                // in local (parent-relative) float coordinates, sidesteps
                // whatever internal rounding the anchor engine does.
                //
                // SETTLED-SNAP: that float x is exactly right mid-spring, but
                // at rest it resamples distance-field glyphs at a fractional
                // device pixel and blurs them (pill text measured soft while
                // idle). Once nothing is animating (Motion.activeCount === 0)
                // there is no shake left to avoid, so round to the nearest
                // device pixel; keep the float while active so this doesn't
                // reintroduce the parity wobble above.
                x: Motion.activeCount > 0
                    ? (parent.width - width) / 2
                    : Math.round((parent.width - width) / 2)
                // Same base as IslandController.targetWidth's dormant branch
                // (incl. restContentWidth), so the content box matches the pill
                // body instead of laying out in a narrower centred box.
                width: (Config.appearance.ink
                    ? Math.max(Math.round(Theme.inkRestMinW * DisplayScale.primary),
                        islandController.restContentWidth)
                    : Math.max(Config.island.dormantWidth,
                        Config.island.restMinimumWidth,
                        islandController.restContentWidth))
                    + (islandController.lyricsVisible ? Config.media.lyricsBandWidth + Config.media.lyricsBandGap : 0)
                    + (islandController.workspaceSwitchActive
                        ? islandController.workspaceIndicatorMax * Theme.u(0.62)
                            + Math.max(0, islandController.workspaceIndicatorMax - 1) * Theme.u(0.14)
                        : 0)
                // Ink: the pill's own height. The legacy 28px box sat at the
                // top of the 38px ink pill, so the clock rode 5px high.
                height: Config.appearance.ink
                    ? Math.round(Theme.inkRestH * DisplayScale.primary)
                    : Config.island.dormantHeight
                // No `!dismissing` gate any more: the incoming resting
                // content fades in CONCURRENTLY with the outgoing expanded
                // content's own fade-out and the geometry morph, not after
                // both finish (see IslandController.dismiss()).
                enabled: islandController.visualState === islandController.dormant
                opacity: window.choreography.active
                    ? window.choreography.opacityFor("dormant") : (enabled ? 1 : 0)
                anchors.topMargin: window.choreography.liftFor("dormant")
                scale: window.choreography.scaleFor("dormant")
                IslandDormant {
                    id: dormantContent
                    anchors.fill: parent
                    shareHosted: true
                    onContentWidthChanged:
                        islandController.restContentWidth = contentWidth
                    Component.onCompleted:
                        islandController.restContentWidth = contentWidth
                    workspaceSwitchActive: islandController.workspaceSwitchActive
                    workspaceIndicatorMax: islandController.workspaceIndicatorMax
                    previousWorkspaceId: islandController.previousWorkspaceId
                    // Control Center is deprecated -- open the dashboard,
                    // not the old control-center page. See HANDOVER.md.
                    onPowerRequested: islandController.openPage("overview")
                    // The resting pill's middle: left and right both open
                    // the dashboard -- IMPASTO REMOVED (see the spec's
                    // section 1 "Removed"): this used to route right-click
                    // to the impasto calendar card (island/cards/
                    // CalendarCard.qml, deleted); both now open the same
                    // dashboard the impasto-off fallback already used.
                    onDashboardRequested: islandController.openPage("overview")
                    onCalendarRequested: islandController.openPage("overview")
                }
                Behavior on opacity { enabled: !window.choreography.active; NumberAnimation { duration: Config.appearance.ink ? 150 : Animations.fast } }
            }

            Item {
                anchors.top: parent.top
                // Explicit float centring, NOT anchors.horizontalCenter --
                // measured directly (debug SHAKE trace, live capture during a
                // real hover morph): Qt Quick's own anchor engine resolves
                // horizontalCenter with a parity-dependent 0.5px quirk of its
                // own (deviates from the algebraically exact parent centre by
                // exactly 0.5px whenever the LIVE, per-frame contentFocus.width
                // -- Math.round(bodyW.value), changing every frame mid-spring --
                // happens to be odd, and 0px when even), even though
                // core/BlobLayout.qml's own centred() already keeps the parent's
                // true centre exactly constant. That 0.5px anchor-engine wobble
                // is what read as "the clock and icons shake while the pill
                // scales" -- the pill body itself never used anchors here (it's
                // pure float math), only its content did. Computing x ourselves,
                // in local (parent-relative) float coordinates, sidesteps
                // whatever internal rounding the anchor engine does.
                //
                // SETTLED-SNAP: that float x is exactly right mid-spring, but
                // at rest it resamples distance-field glyphs at a fractional
                // device pixel and blurs them (pill text measured soft while
                // idle). Once nothing is animating (Motion.activeCount === 0)
                // there is no shake left to avoid, so round to the nearest
                // device pixel; keep the float while active so this doesn't
                // reintroduce the parity wobble above.
                x: Motion.activeCount > 0
                    ? (parent.width - width) / 2
                    : Math.round((parent.width - width) / 2)
                // Ink: the content box must be the pill's own 420x52
                // (IslandController's ink hover target). The legacy 470+ box
                // centred over a 420 pill hung its art and status cluster off
                // both edges, so the title looked clipped on the left.
                width: Config.appearance.ink
                    ? Math.round(Theme.inkHoverW * DisplayScale.primary)
                    : MediaService.hoverVisible
                    ? Math.max(Config.island.hoverWidth,
                        Config.island.hoverMediaMinimumWidth)
                    : Math.max(Config.island.hoverWidth,
                        Config.island.hoverMinimumWidth)
                height: Config.appearance.ink
                    ? Math.round(Theme.inkHoverH * DisplayScale.primary)
                    : Config.island.hoverHeight
                // See the resting Item above: same concurrency reasoning.
                enabled: islandController.visualState === islandController.hover
                opacity: window.choreography.active
                    ? window.choreography.opacityFor("hover") : (enabled ? 1 : 0)
                anchors.topMargin: window.choreography.liftFor("hover")
                scale: window.choreography.scaleFor("hover")
                IslandHover {
                    id: hoverContent
                    anchors.fill: parent
                    shareHosted: true
                    monitor: window.monitor
                    // Control Center is deprecated -- open the dashboard,
                    // not the old control-center page. See HANDOVER.md.
                    // The Wi-Fi/Bluetooth/Audio capsule glyphs open their
                    // satellite directly (blob-rebuild spec section 3/4),
                    // same pipeline ShellActions.controlCenterSectionRequested
                    // and `island satellite <name>` IPC use. "battery" opens
                    // the energy satellite; everything else just opens the
                    // dashboard, same as the impasto-off path already did
                    // before this pass.
                    onControlCenterRequested: card => {
                        islandController.openPage("overview")
                        if (card === "wifi" || card === "bluetooth")
                            expandedContent.openSatellite(card)
                        else if (card === "volume")
                            expandedContent.openSatellite("audio")
                        else if (card === "battery")
                            expandedContent.openSatellite("energy")
                    }
                }
                Behavior on opacity { enabled: !window.choreography.active; NumberAnimation { duration: Config.appearance.ink ? 150 : Animations.fast } }
            }

            Item {
                anchors.top: parent.top
                // Explicit float centring, NOT anchors.horizontalCenter --
                // measured directly (debug SHAKE trace, live capture during a
                // real hover morph): Qt Quick's own anchor engine resolves
                // horizontalCenter with a parity-dependent 0.5px quirk of its
                // own (deviates from the algebraically exact parent centre by
                // exactly 0.5px whenever the LIVE, per-frame contentFocus.width
                // -- Math.round(bodyW.value), changing every frame mid-spring --
                // happens to be odd, and 0px when even), even though
                // core/BlobLayout.qml's own centred() already keeps the parent's
                // true centre exactly constant. That 0.5px anchor-engine wobble
                // is what read as "the clock and icons shake while the pill
                // scales" -- the pill body itself never used anchors here (it's
                // pure float math), only its content did. Computing x ourselves,
                // in local (parent-relative) float coordinates, sidesteps
                // whatever internal rounding the anchor engine does.
                //
                // SETTLED-SNAP: that float x is exactly right mid-spring, but
                // at rest it resamples distance-field glyphs at a fractional
                // device pixel and blurs them (pill text measured soft while
                // idle). Once nothing is animating (Motion.activeCount === 0)
                // there is no shake left to avoid, so round to the nearest
                // device pixel; keep the float while active so this doesn't
                // reintroduce the parity wobble above.
                x: Motion.activeCount > 0
                    ? (parent.width - width) / 2
                    : Math.round((parent.width - width) / 2)
                // Keep expanded content at stable final geometry while the
                // containing surface clips across its enter/exit morph.
                // One size table, not two: islandController.expandedTargetWidth/
                // Height is the same expression targetWidth/targetHeight use
                // for the expanded state, read directly so this host stays at
                // the page's real final geometry while the surface clips
                // across its enter/exit morph. It used to restate the table
                // here, which went stale the moment the impasto per-state
                // panel sizes landed -- cards drew into a correctly sized
                // slab with content still laid out at Config.insights.width,
                // so every card read as an empty black box with its content
                // clipped away.
                width: islandController.expandedTargetWidth
                height: islandController.expandedTargetHeight
                enabled: islandController.expandedPresentationActive
                opacity: window.choreography.active
                    ? window.choreography.opacityFor("expanded")
                    : (islandController.expandedActive ? 1 : 0)
                anchors.topMargin: window.choreography.liftFor("expanded")
                scale: window.choreography.scaleFor("expanded")
                IslandExpanded {
                    id: expandedContent
                    anchors.fill: parent
                    monitor: window.monitor
                    screen: window.screen
                    page: islandController.expandedPage
                    active: islandController.expandedActive
                    messagesThreadId: islandController.messagesThreadId
                    onPageSelected: selectedPage =>
                        islandController.expandedPage = selectedPage
                    onDismissRequested: forceDormant =>
                        islandController.dismiss(forceDormant)
                }
                // IMPASTO REMOVED: these Bindings used to keep
                // IslandController.dashboardInnerPage/dashboardDetailModuleId
                // (both deleted) in step with dashboard/DashDashboard.qml's
                // own `page`/`detailModuleId`, so the pill's target size
                // followed whichever impasto panel the dashboard was
                // showing. The dashboard is now always panels/Dashboard.qml,
                // sized from the plain Config.dashboard entry instead.
                Behavior on opacity {
                    enabled: !window.choreography.active
                    NumberAnimation {
                        duration: Config.appearance.ink ? 150 : islandController.dismissing
                            ? Animations.fast : Animations.normal
                    }
                }
            }

            Item {
                anchors.top: parent.top
                // Explicit float centring, NOT anchors.horizontalCenter --
                // measured directly (debug SHAKE trace, live capture during a
                // real hover morph): Qt Quick's own anchor engine resolves
                // horizontalCenter with a parity-dependent 0.5px quirk of its
                // own (deviates from the algebraically exact parent centre by
                // exactly 0.5px whenever the LIVE, per-frame contentFocus.width
                // -- Math.round(bodyW.value), changing every frame mid-spring --
                // happens to be odd, and 0px when even), even though
                // core/BlobLayout.qml's own centred() already keeps the parent's
                // true centre exactly constant. That 0.5px anchor-engine wobble
                // is what read as "the clock and icons shake while the pill
                // scales" -- the pill body itself never used anchors here (it's
                // pure float math), only its content did. Computing x ourselves,
                // in local (parent-relative) float coordinates, sidesteps
                // whatever internal rounding the anchor engine does.
                //
                // SETTLED-SNAP: that float x is exactly right mid-spring, but
                // at rest it resamples distance-field glyphs at a fractional
                // device pixel and blurs them (pill text measured soft while
                // idle). Once nothing is animating (Motion.activeCount === 0)
                // there is no shake left to avoid, so round to the nearest
                // device pixel; keep the float while active so this doesn't
                // reintroduce the parity wobble above.
                x: Motion.activeCount > 0
                    ? (parent.width - width) / 2
                    : Math.round((parent.width - width) / 2)
                // Sized through IslandController's own targetWidth/Height --
                // see island/IslandOSD.qml -- not a Config literal.
                width: islandController.targetWidth
                height: islandController.targetHeight
                enabled: islandController.transientActive
                    && islandController.visualState !== islandController.media
                    && islandController.visualState !== islandController.notification
                    && islandController.visualState !== islandController.switcher
                    && islandController.visualState !== islandController.battery
                    && islandController.visualState !== islandController.timerDone
                    && !islandController.phoneState
                opacity: window.choreography.active
                    ? window.choreography.opacityFor("osd") : (enabled ? 1 : 0)
                anchors.topMargin: window.choreography.liftFor("osd")
                scale: window.choreography.scaleFor("osd")
                IslandOSD {
                    anchors.fill: parent
                    kind: islandController.transientState
                    level: islandController.transientLevel
                    muted: islandController.transientMuted
                    deviceName: islandController.transientDeviceName
                }
                Behavior on opacity { enabled: !window.choreography.active; NumberAnimation { duration: Config.appearance.ink ? 150 : Animations.fast } }
            }

            Item {
                anchors.top: parent.top
                // Explicit float centring, NOT anchors.horizontalCenter --
                // measured directly (debug SHAKE trace, live capture during a
                // real hover morph): Qt Quick's own anchor engine resolves
                // horizontalCenter with a parity-dependent 0.5px quirk of its
                // own (deviates from the algebraically exact parent centre by
                // exactly 0.5px whenever the LIVE, per-frame contentFocus.width
                // -- Math.round(bodyW.value), changing every frame mid-spring --
                // happens to be odd, and 0px when even), even though
                // core/BlobLayout.qml's own centred() already keeps the parent's
                // true centre exactly constant. That 0.5px anchor-engine wobble
                // is what read as "the clock and icons shake while the pill
                // scales" -- the pill body itself never used anchors here (it's
                // pure float math), only its content did. Computing x ourselves,
                // in local (parent-relative) float coordinates, sidesteps
                // whatever internal rounding the anchor engine does.
                //
                // SETTLED-SNAP: that float x is exactly right mid-spring, but
                // at rest it resamples distance-field glyphs at a fractional
                // device pixel and blurs them (pill text measured soft while
                // idle). Once nothing is animating (Motion.activeCount === 0)
                // there is no shake left to avoid, so round to the nearest
                // device pixel; keep the float while active so this doesn't
                // reintroduce the parity wobble above.
                x: Motion.activeCount > 0
                    ? (parent.width - width) / 2
                    : Math.round((parent.width - width) / 2)
                width: Config.appearance.ink ? Math.round(560 * DisplayScale.primary) : Config.island.mediaWidth
                height: Config.appearance.ink ? Math.round(232 * DisplayScale.primary) : Config.island.mediaHeight
                enabled: islandController.visualState === islandController.media
                opacity: window.choreography.active
                    ? window.choreography.opacityFor("media") : (enabled ? 1 : 0)
                anchors.topMargin: window.choreography.liftFor("media")
                scale: window.choreography.scaleFor("media")
                IslandMedia { id: mediaContent; anchors.fill: parent }
                Behavior on opacity { enabled: !window.choreography.active; NumberAnimation { duration: Config.appearance.ink ? 150 : Animations.fast } }
            }

            // Alt+Tab app switcher (island/IslandSwitcher.qml). Same centring
            // and sizing contract as the OSD and media hosts above.
            Item {
                anchors.top: parent.top
                x: Motion.activeCount > 0
                    ? (parent.width - width) / 2
                    : Math.round((parent.width - width) / 2)
                width: islandController.targetWidth
                height: islandController.targetHeight
                enabled: islandController.visualState === islandController.switcher
                opacity: window.choreography.active
                    ? window.choreography.opacityFor("switcher") : (enabled ? 1 : 0)
                anchors.topMargin: window.choreography.liftFor("switcher")
                scale: window.choreography.scaleFor("switcher")
                IslandSwitcher {
                    anchors.fill: parent
                    controller: islandController
                }
                Behavior on opacity { enabled: !window.choreography.active; NumberAnimation { duration: Config.appearance.ink ? 150 : Animations.fast } }
            }

            Item {
                anchors.top: parent.top
                // Explicit float centring, NOT anchors.horizontalCenter --
                // measured directly (debug SHAKE trace, live capture during a
                // real hover morph): Qt Quick's own anchor engine resolves
                // horizontalCenter with a parity-dependent 0.5px quirk of its
                // own (deviates from the algebraically exact parent centre by
                // exactly 0.5px whenever the LIVE, per-frame contentFocus.width
                // -- Math.round(bodyW.value), changing every frame mid-spring --
                // happens to be odd, and 0px when even), even though
                // core/BlobLayout.qml's own centred() already keeps the parent's
                // true centre exactly constant. That 0.5px anchor-engine wobble
                // is what read as "the clock and icons shake while the pill
                // scales" -- the pill body itself never used anchors here (it's
                // pure float math), only its content did. Computing x ourselves,
                // in local (parent-relative) float coordinates, sidesteps
                // whatever internal rounding the anchor engine does.
                //
                // SETTLED-SNAP: that float x is exactly right mid-spring, but
                // at rest it resamples distance-field glyphs at a fractional
                // device pixel and blurs them (pill text measured soft while
                // idle). Once nothing is animating (Motion.activeCount === 0)
                // there is no shake left to avoid, so round to the nearest
                // device pixel; keep the float while active so this doesn't
                // reintroduce the parity wobble above.
                x: Motion.activeCount > 0
                    ? (parent.width - width) / 2
                    : Math.round((parent.width - width) / 2)
                // See island/IslandController.qml's targetWidth/Height
                // (Theme.u(9.44) x Theme.u(2.1) while visualState is
                // "notification") -- not a Config literal.
                width: islandController.targetWidth
                height: islandController.targetHeight
                enabled: islandController.visualState === islandController.notification
                    && !islandController.notificationDismissing
                opacity: window.choreography.active
                    ? window.choreography.opacityFor("notification") * (islandController.notificationDismissing ? 0 : 1)
                    : (islandController.visualState === islandController.notification
                        && !islandController.notificationDismissing ? 1 : 0)
                anchors.topMargin: window.choreography.liftFor("notification")
                scale: window.choreography.scaleFor("notification")
                IslandNotification { anchors.fill: parent; controller: islandController }
                Behavior on opacity {
                    enabled: !window.choreography.active || islandController.notificationDismissing
                    NumberAnimation {
                        duration: Animations.fast
                        easing.type: Animations.standardEase
                    }
                }
            }

            // iPhone continuity states (island/Phone*.qml). Same centring and
            // sizing contract as the notification host above.
            Item {
                anchors.top: parent.top
                x: Motion.activeCount > 0
                    ? (parent.width - width) / 2
                    : Math.round((parent.width - width) / 2)
                width: islandController.targetWidth
                height: islandController.targetHeight
                enabled: islandController.visualState === islandController.call
                opacity: window.choreography.active
                    ? window.choreography.opacityFor("call") : (enabled ? 1 : 0)
                anchors.topMargin: window.choreography.liftFor("call")
                scale: window.choreography.scaleFor("call")
                PhoneCallCard { anchors.fill: parent }
                Behavior on opacity { enabled: !window.choreography.active; NumberAnimation { duration: Config.appearance.ink ? 150 : Animations.fast } }
            }

            Item {
                anchors.top: parent.top
                x: Motion.activeCount > 0
                    ? (parent.width - width) / 2
                    : Math.round((parent.width - width) / 2)
                width: islandController.targetWidth
                height: islandController.targetHeight
                enabled: islandController.visualState === islandController.callActive
                opacity: window.choreography.active
                    ? window.choreography.opacityFor("callActive") : (enabled ? 1 : 0)
                anchors.topMargin: window.choreography.liftFor("callActive")
                scale: window.choreography.scaleFor("callActive")
                PhoneCallPill {
                    anchors.fill: parent
                    expanded: islandController.callPillExpanded
                    onToggleRequested: islandController.callPillExpanded = true
                }
                Behavior on opacity { enabled: !window.choreography.active; NumberAnimation { duration: Config.appearance.ink ? 150 : Animations.fast } }
            }

            Item {
                anchors.top: parent.top
                x: Motion.activeCount > 0
                    ? (parent.width - width) / 2
                    : Math.round((parent.width - width) / 2)
                width: islandController.targetWidth
                height: islandController.targetHeight
                enabled: islandController.visualState === islandController.phoneMessage
                opacity: window.choreography.active
                    ? window.choreography.opacityFor("phoneMessage") : (enabled ? 1 : 0)
                anchors.topMargin: window.choreography.liftFor("phoneMessage")
                scale: window.choreography.scaleFor("phoneMessage")
                PhoneMessageToast {
                    anchors.fill: parent
                    controller: islandController
                    entry: islandController.phoneMessageEntry
                    onOpenThread: threadId => {
                        islandController.openMessages(threadId)
                    }
                }
                Behavior on opacity { enabled: !window.choreography.active; NumberAnimation { duration: Config.appearance.ink ? 150 : Animations.fast } }
            }

            Item {
                anchors.top: parent.top
                x: Motion.activeCount > 0
                    ? (parent.width - width) / 2
                    : Math.round((parent.width - width) / 2)
                width: islandController.targetWidth
                height: islandController.targetHeight
                enabled: islandController.visualState === islandController.airplayPin
                opacity: window.choreography.active
                    ? window.choreography.opacityFor("airplayPin") : (enabled ? 1 : 0)
                anchors.topMargin: window.choreography.liftFor("airplayPin")
                scale: window.choreography.scaleFor("airplayPin")
                PhoneAirplayPin { anchors.fill: parent }
                Behavior on opacity { enabled: !window.choreography.active; NumberAnimation { duration: Config.appearance.ink ? 150 : Animations.fast } }
            }

            Item {
                anchors.top: parent.top
                x: Motion.activeCount > 0
                    ? (parent.width - width) / 2
                    : Math.round((parent.width - width) / 2)
                width: islandController.targetWidth
                height: islandController.targetHeight
                enabled: islandController.visualState === islandController.mirroring
                opacity: window.choreography.active
                    ? window.choreography.opacityFor("mirroring") : (enabled ? 1 : 0)
                anchors.topMargin: window.choreography.liftFor("mirroring")
                scale: window.choreography.scaleFor("mirroring")
                PhoneLivePill { anchors.fill: parent; kind: "mirroring" }
                Behavior on opacity { enabled: !window.choreography.active; NumberAnimation { duration: Config.appearance.ink ? 150 : Animations.fast } }
            }

            Item {
                anchors.top: parent.top
                x: Motion.activeCount > 0
                    ? (parent.width - width) / 2
                    : Math.round((parent.width - width) / 2)
                width: islandController.targetWidth
                height: islandController.targetHeight
                enabled: islandController.visualState === islandController.camera
                opacity: window.choreography.active
                    ? window.choreography.opacityFor("camera") : (enabled ? 1 : 0)
                anchors.topMargin: window.choreography.liftFor("camera")
                scale: window.choreography.scaleFor("camera")
                PhoneLivePill { anchors.fill: parent; kind: "camera" }
                Behavior on opacity { enabled: !window.choreography.active; NumberAnimation { duration: Config.appearance.ink ? 150 : Animations.fast } }
            }

            // Pomodoro / timer finished (island/TimerDoneToast.qml). Same
            // centring and sizing contract as the notification host.
            Item {
                anchors.top: parent.top
                x: Motion.activeCount > 0
                    ? (parent.width - width) / 2
                    : Math.round((parent.width - width) / 2)
                width: islandController.targetWidth
                height: islandController.targetHeight
                enabled: islandController.visualState === islandController.timerDone
                opacity: window.choreography.active
                    ? window.choreography.opacityFor("osd") : (enabled ? 1 : 0)
                anchors.topMargin: window.choreography.liftFor("osd")
                scale: window.choreography.scaleFor("osd")
                TimerDoneToast {
                    anchors.fill: parent
                    label: islandController.timerDoneLabel
                    breakOver: islandController.timerDoneBreakOver
                }
                Behavior on opacity { enabled: !window.choreography.active; NumberAnimation { duration: Config.appearance.ink ? 150 : Animations.fast } }
            }

            // Ink shared-element layer (island/SharedElements.qml). Last child
            // so it draws over every state, in the pill's own space and clip.
            // The active state picks its SharePoint tags; see that file.
            SharedElements {
                id: sharedElements
                choreo: window.choreography
                placeholders: [].concat(dormantContent.shareItems, hoverContent.shareItems,
                    mediaContent.shareItems, expandedContent.shareItems)
            }
            }
        }

        HoverHandler {
            onHoveredChanged: {
                if (window.inputTrace) console.log("INPUT hover surface=" + hovered + " t=" + Date.now())
                hovered ? islandController.enter() : islandController.leave()
            }
        }
        TapHandler {
            enabled: !islandController.expandedPresentationActive
                && islandController.visualState !== islandController.notification
                && islandController.visualState !== islandController.switcher
                && !islandController.phoneState
                && !(islandController.visualState === islandController.dormant
                    && (dormantContent.powerHovered || dormantContent.timerHovered))
            onTapped: islandController.toggleExpanded()
        }

        // Battery OSD for power plug/unplug and low charge. Driven by the
        // controller's `battery` transient (priority 40), not its own timer.
        BatteryOSD {
            id: batteryOSD
            anchors.centerIn: parent
            shown: islandController.transientState === islandController.battery
        }
    }

    SequentialAnimation {
        id: powerConnectedPulse
        NumberAnimation {
            target: window
            property: "pillPulse"
            from: 0
            to: 1
            duration: Config.animations.profileFeedbackRise
            easing.type: Easing.OutCubic
        }
        PauseAnimation {
            duration: Config.animations.profileFeedbackHold
        }
        NumberAnimation {
            target: window
            property: "pillPulse"
            to: 0
            duration: Config.animations.profileFeedbackFade
            easing.type: Easing.OutQuart
        }
    }

    // ---- Wi-Fi / Bluetooth / Audio satellites ---------------------------
    // Blob bodies 1 (left, Wi-Fi) and 2 (right, Bluetooth/Audio/tray) --
    // NOT separate Surface rectangles any more (blob-rebuild spec section
    // 1: "satellites are blob bodies... not separate Surfaces"). Their
    // CONTENT (ControlDetailPanel/TraySatellitePanel) is unchanged; what's
    // gone is each one's own visible Surface fill -- BlobSurface above
    // draws the merged shape for all three bodies in one shader pass, and
    // these Items are now just geometry (for the shader's bodies[] array
    // and the input mask) plus a `clip: true` content host.
    // x/w/r come from window.blobLayout (see its own header for why it's
    // computed with wifiOpen/bluetoothOpen forced true -- these Items are
    // where the REAL open/close state actually lives, via heightMV).
    Item {
        id: wifiSatellite
        PointHandler {
            enabled: window.inputTrace
            onActiveChanged: if (active) console.log("INPUT press wifiSatellite t=" + Date.now())
        }
        readonly property real radius: window.blobLayout.bodies[1].r
        property MotionValue neckMV: MotionValue {
            unit: "px"
            omega: Motion.presetBouncy().omega / Math.max(0.25, Config.appearance.motionScale)
            zeta: Motion.presetBouncy().zeta
            // Always targets the STEADY joined/separate neck strength
            // (core/BlobLayout.qml's ctx.satelliteJoin) regardless of open
            // state -- harmless while closed (an absent/zero-size body's
            // SDF is ~1e6 regardless of k), and it's exactly this bouncy
            // spring's overshoot, starting from 0 the first time it opens,
            // that reads as the neck springing "from large to resting".
            target: window.blobLayout.neckK[0]
        }
        x: window.blobLayout.bodies[1].x
        y: Math.round(window.bodyY.value)
        width: window.blobLayout.bodies[1].w
        // Ink: size comes from the detach progress (BlobLayout), not heightMV.
        height: Config.appearance.ink ? window.blobLayout.bodies[1].h : Math.round(heightMV.value)
        clip: true
        visible: height > 1
        // Ink: content only once the satellite has floated free (gap > 0), so
        // text never sits inside the neck; it fades out on close, before the
        // re-merge. Legacy: plain open/closed.
        opacity: Config.appearance.ink
            ? (expandedContent.wifiSatelliteVisible && window.blobLayout.inkGap[0] > 0 ? 1 : 0)
            : (expandedContent.wifiSatelliteVisible ? 1 : 0)

        property MotionValue heightMV: MotionValue {
            unit: "px"
            omega: Motion.presetSmooth().omega / Math.max(0.25, Config.appearance.motionScale)
            zeta: Motion.presetSmooth().zeta
            target: expandedContent.wifiSatelliteVisible
                ? window.blobLayout.bodies[1].h : 0
        }

        ControlDetailPanel {
            id: wifiPanel
            anchors.fill: parent
            controller: expandedContent.controlCenter
            section: "wifi"
        }

        Behavior on opacity { NumberAnimation { duration: Config.appearance.ink ? 180 : Animations.normal } }
    }

    // The right satellite hosts EITHER Bluetooth or Audio -- never both --
    // so ControlCenter.qml closes one whenever the other opens (see
    // toggleSatellite there). Its geometry doesn't change per section, only
    // which ControlDetailPanel section it renders, so the input mask below
    // (which references this Item by id) needs no changes either.
    Item {
        id: bluetoothSatellite
        // Tray menus share this same right-satellite geometry -- a third,
        // mutually-exclusive mode alongside Bluetooth/Audio (see
        // ControlCenter.qml's traySatelliteOpen/toggleTrayMenu).
        readonly property bool traySatelliteVisible:
            expandedContent.traySatelliteVisible
        // Read straight off the (public) SatelliteState so the Energy
        // section needs no new IslandExpanded plumbing.
        readonly property bool energySatelliteVisible:
            expandedContent.satelliteState.rightSection === "energy"
        readonly property bool phoneSatelliteVisible:
            expandedContent.phoneSatelliteVisible
        readonly property bool rightSatelliteVisible:
            expandedContent.bluetoothSatelliteVisible || expandedContent.audioSatelliteVisible
                || traySatelliteVisible || energySatelliteVisible || phoneSatelliteVisible
        readonly property string rightSatelliteSection:
            traySatelliteVisible ? "tray"
                : phoneSatelliteVisible ? "phone"
                : energySatelliteVisible ? "energy"
                : expandedContent.audioSatelliteVisible ? "audio" : "bluetooth"
        readonly property real radius: window.blobLayout.bodies[2].r
        property MotionValue neckMV: MotionValue {
            unit: "px"
            omega: Motion.presetBouncy().omega / Math.max(0.25, Config.appearance.motionScale)
            zeta: Motion.presetBouncy().zeta
            target: window.blobLayout.neckK[1]
        }
        PointHandler {
            enabled: window.inputTrace
            onActiveChanged: if (active) console.log("INPUT press bluetoothSatellite t=" + Date.now())
        }
        x: window.blobLayout.bodies[2].x
        y: Math.round(window.bodyY.value)
        width: window.blobLayout.bodies[2].w
        height: Config.appearance.ink ? window.blobLayout.bodies[2].h : Math.round(heightMV.value)
        clip: true
        visible: height > 1
        // Ink: same gating as the Wi-Fi satellite (content after detach only).
        opacity: Config.appearance.ink
            ? (rightSatelliteVisible && window.blobLayout.inkGap[1] > 0 ? 1 : 0)
            : (rightSatelliteVisible ? 1 : 0)

        property MotionValue heightMV: MotionValue {
            unit: "px"
            omega: Motion.presetSmooth().omega / Math.max(0.25, Config.appearance.motionScale)
            zeta: Motion.presetSmooth().zeta
            target: bluetoothSatellite.rightSatelliteVisible
                ? window.blobLayout.bodies[2].h : 0
        }

        // Bluetooth/Audio/tray share this ONE satellite footprint, so
        // switching between them (toggleSatellite) is a content swap, not a
        // resize -- window.blobLayout.bodies[2].h doesn't change, only
        // rightPanelLoader's sourceComponent does. A bare Loader swap
        // recreates its item synchronously with zero transition, which
        // read as a hard content cut (audio sliders replacing the
        // Bluetooth device list mid-frame) even though the satellite BODY
        // itself was never snapping. Reveal -- the same fade+rise wrapper
        // every island/IslandExpanded.qml page already uses on ITS OWN
        // page switches -- softens this the identical way: bump `token`
        // whenever the section changes, and the outgoing content's own
        // fade-out (this Reveal's exit leg) covers the instant under it.
        Reveal {
            anchors.fill: parent
            token: bluetoothSatellite._sectionToken
            order: 0
            Loader {
                id: rightPanelLoader
                anchors.fill: parent
                sourceComponent: bluetoothSatellite.rightSatelliteSection === "tray"
                    ? trayPanelComponent
                    : bluetoothSatellite.rightSatelliteSection === "phone"
                        ? phonePanelComponent
                    : bluetoothSatellite.rightSatelliteSection === "energy"
                        ? energyPanelComponent
                    : bluetoothSatellite.rightSatelliteSection === "audio"
                        ? audioPanelComponent : detailPanelComponent
            }
        }
        property int _sectionToken: 0
        onRightSatelliteSectionChanged: bluetoothSatellite._sectionToken++

        Behavior on opacity { NumberAnimation { duration: Config.appearance.ink ? 180 : Animations.normal } }
    }

    Component {
        id: detailPanelComponent
        ControlDetailPanel {
            controller: expandedContent.controlCenter
            section: bluetoothSatellite.rightSatelliteSection
        }
    }

    // Self-contained -- AudioSatelliteContent reads AudioService/Pipewire
    // directly (device lists, setOutput/setInput), unlike ControlDetailPanel's
    // own older "audio" section which needs the shared ControlCenter
    // controller. Replaces bluetooth when open (ControlCenter.toggleSatellite
    // already enforces the two are mutually exclusive on this one right-hand
    // slot).
    Component {
        id: audioPanelComponent
        AudioSatelliteContent {}
    }

    // Energy is only instantiated while it is THE right-satellite section
    // (Loader above), and `active` additionally requires the satellite to
    // still be logically open, so the ledger watch stops the moment it
    // closes (opacity fades out after, which is exactly the trap avoided).
    Component {
        id: energyPanelComponent
        Item {
            EnergyList {
                id: energyList
                anchors.fill: parent
                anchors.margins: Theme.u(0.44)
                active: bluetoothSatellite.energySatelliteVisible
            }
            Text {
                anchors.centerIn: parent
                visible: !EnergyService.available
                text: "No energy data"
                color: AdaptiveColor.glassTextDim
                font.family: Config.appearance.fontFamily
                font.pixelSize: Theme.textSmall
            }
        }
    }

    // Only instantiated while "phone" is the right-satellite section.
    Component {
        id: phonePanelComponent
        PhoneSatelliteContent {
            onOpenMessagesRequested: islandController.openMessages("")
        }
    }

    Component {
        id: trayPanelComponent
        TraySatellitePanel {
            item: expandedContent.traySatelliteItem
        }
    }

    // The target remains at the physical edge while hidden/fullscreen. The
    // visual lip is optional and is always suppressed over fullscreen content.
    Rectangle {
        id: revealTarget
        visible: islandController.revealOnly && !window.liveEditActive
        x: Math.round((parent.width - width) / 2)
        y: 0
        width: Math.max(Config.island.dormantWidth,
            Config.island.restMinimumWidth)
        height: Config.island.revealHeight
        color: "transparent"

        HoverHandler {
            onHoveredChanged: hovered ? islandController.enter()
                : islandController.leave()
        }

        Surface {
            id: revealStrip
            anchors.fill: parent
            visible: Config.island.showRevealLip && !islandController.fullscreen
            radius: height / 2
            color: window.pillFillColor
            border.color: Qt.rgba(1, 1, 1, 0.28)
        }
    }

    Surface {
        id: liveEditPreview
        visible: window.liveEditActive
        enabled: false
        clip: true
        x: Math.round((parent.width - width) / 2)
        y: 0
        // Target (final) geometry, kept separate from the animated width/
        // height below so the content Item can be sized off it directly --
        // same "content keeps its final geometry while the surface clips
        // across the morph" pattern as the main surface's own content
        // Items above, extended here to this preview surface too.
        readonly property real targetW: window.liveEditMode === "hover"
            ? (MediaService.hoverVisible && Config.island.hoverShowMedia
                ? Math.max(Config.island.hoverWidth,
                    Config.island.hoverMediaMinimumWidth)
                : Math.max(Config.island.hoverWidth,
                    Config.island.hoverMinimumWidth))
            : Math.max(Config.island.dormantWidth,
                Config.island.restMinimumWidth)
        readonly property real targetH: window.liveEditPreviewHeight
        width: Math.round(previewW.value)
        height: Math.round(previewH.value)
        radius: Theme.radiusLarge
        color: Theme.islandSurface
        border.color: Qt.alpha(Theme.outlineVariant,
            Theme.dark ? 0.62 : 0.48)
        opacity: visible ? 1 : 0

        // MotionValue springs, not duration clips -- same primitive as the
        // main island surface (Island.qml above), so this preview tracks a
        // rapid mode switch the same way the real surface does. Direction
        // read off target-vs-value per spring, per Motion.qml's enter/exit
        // presets.
        // Direction locked once per retarget by MotionValue itself
        // (omegaEnter/omegaExit -- see core/MotionValue.qml's header),
        // not re-derived every frame from `target >= value`: that read
        // this spring's own live value every frame, which can flip near
        // an overshoot crossing and rewrite omega/zeta out from under
        // the closed-form basis mid-flight (the actual vibration bug).
        property MotionValue previewW: MotionValue {
            unit: "px"
            target: liveEditPreview.targetW
            omegaEnter: Motion.omegaEnter / Math.max(0.25, Config.appearance.motionScale)
            zetaEnter: Motion.zetaEnter
            omegaExit: Motion.omegaExit / Math.max(0.25, Config.appearance.motionScale)
            zetaExit: Motion.zetaExit
        }
        property MotionValue previewH: MotionValue {
            unit: "px"
            target: liveEditPreview.targetH
            omegaEnter: Motion.omegaEnter / Math.max(0.25, Config.appearance.motionScale)
            zetaEnter: Motion.zetaEnter
            omegaExit: Motion.omegaExit / Math.max(0.25, Config.appearance.motionScale)
            zetaExit: Motion.zetaExit
        }

        // Fixed at the surface's TARGET size (not width/height above, which
        // animate) so IslandDormant/IslandHover's own RowLayouts never
        // relayout mid-spring -- they only ever see their final geometry.
        Item {
            anchors.centerIn: parent
            width: liveEditPreview.targetW
            height: liveEditPreview.targetH
            IslandDormant {
                anchors.fill: parent
                visible: window.liveEditMode === "rest"
            }
            IslandHover {
                anchors.fill: parent
                visible: window.liveEditMode === "hover"
                monitor: window.monitor
            }
        }

        Behavior on opacity { NumberAnimation { duration: Animations.normal } }
    }

    Connections {
        target: islandController
        function onVisualStateChanged(): void {
            // Leaving the expanded page for ANY other state (switcher, OSD,
            // notification, media, rest) closes the satellites in the same
            // morph, through their normal droplet re-merge, so they are
            // never left hosted beside a transient state.
            if (islandController.visualState !== islandController.expanded
                    && expandedContent.satelliteState.anyOpen)
                expandedContent.closeSatellite()
            if (islandController.expandedActive)
                Qt.callLater(() => contentFocus.forceActiveFocus())
        }
    }

    // FAIL CLOSED: dismiss() is the one function every path that closes the
    // island runs through -- Escape's fallback, HyprlandFocusGrab.onCleared
    // (click-away), and anything else. If the polkit page was showing when
    // that happens, cancel whichever controller was driving it.
    Connections {
        target: islandController
        function onDismissingChanged(): void {
            if (!islandController.dismissing
                    || islandController.expandedPage !== "polkit")
                return
            if (PolkitPreviewService.previewing)
                PolkitPreviewService.cancel()
            else
                PolkitService.cancel()
        }
    }

    Connections {
        target: PolkitService
        function onAuthenticationRequestStarted(): void {
            // Focused-monitor only, same gate every other transient/page
            // open already uses in this file.
            if (window.presentationTarget)
                islandController.openPage("polkit")
        }
    }

    Connections {
        target: PolkitPreviewService
        function onPreviewingChanged(): void {
            if (PolkitPreviewService.previewing && window.presentationTarget)
                islandController.openPage("polkit")
        }
    }

    Connections {
        target: islandController
        function onTransientDismissAnimationFinished(): void {
            if (window.presentationTarget)
                NotificationService.completeTransientDismiss()
        }
    }

    // Alt+Tab. next/prev open the switcher only on the presentation island;
    // commit/cancel are no-ops on any island that is not showing it.
    Connections {
        target: ShellActions
        function onSwitcherNextRequested(): void {
            if (window.presentationTarget)
                islandController.stepSwitcher(1)
        }
        function onSwitcherPrevRequested(): void {
            if (window.presentationTarget)
                islandController.stepSwitcher(-1)
        }
        function onSwitcherCommitRequested(): void {
            islandController.commitSwitcher()
        }
        function onSwitcherCancelRequested(): void {
            islandController.closeSwitcher()
        }
    }

    Connections {
        target: ShellActions
        function onLauncherToggleRequested(): void {
            if (window.presentationTarget)
                islandController.togglePage("launcher")
        }
        function onLauncherOpenRequested(): void {
            if (window.presentationTarget)
                islandController.openPage("launcher")
        }
        function onLauncherCloseRequested(): void {
            islandController.closePage("launcher")
        }
        function onCommandLauncherToggleRequested(): void {
            if (window.presentationTarget)
                islandController.togglePage("command-launcher")
        }
        function onCommandLauncherOpenRequested(): void {
            if (window.presentationTarget)
                islandController.openPage("command-launcher")
        }
        function onCommandLauncherCloseRequested(): void {
            islandController.closePage("command-launcher")
        }
        // Control Center is deprecated (see HANDOVER.md) -- these IPC
        // functions are kept as aliases onto the overview dashboard, and
        // section() now opens the named satellite directly instead of
        // routing through the old control-center page.
        function onControlCenterToggleRequested(): void {
            if (window.presentationTarget)
                islandController.togglePage("overview")
        }
        function onControlCenterOpenRequested(): void {
            if (window.presentationTarget)
                islandController.openPage("overview")
        }
        function onControlCenterCloseRequested(): void {
            islandController.closePage("overview")
        }
        function onControlCenterSectionRequested(section): void {
            if (window.presentationTarget) {
                islandController.openPage("overview")
                expandedContent.openSatellite(section)
            }
        }
        // `island page overview|notes|todo|pet|dashboard` IPC -- direct
        // navigation, always opens to that exact page (openPage(), not a
        // toggle) so a script can drive dashboard<->subpage forward/back
        // deterministically without needing to know current state.
        function onIslandPageRequested(page): void {
            if (window.presentationTarget)
                islandController.openPage(page)
        }
        function onClipboardToggleRequested(): void {
            if (window.presentationTarget)
                islandController.togglePage("clipboard")
        }
        function onClipboardOpenRequested(): void {
            if (window.presentationTarget)
                islandController.openPage("clipboard")
        }
        function onClipboardCloseRequested(): void {
            islandController.closePage("clipboard")
        }
        function onNotificationsToggleRequested(): void {
            if (window.presentationTarget)
                islandController.togglePage("notifications")
        }
        function onNotificationsOpenRequested(): void {
            if (window.presentationTarget)
                islandController.openPage("notifications")
        }
        function onNotificationsCloseRequested(): void {
            islandController.closePage("notifications")
        }
        function onSessionOpenRequested(): void {
            if (window.presentationTarget)
                islandController.openPage("session")
        }
        function onSessionCloseRequested(): void {
            islandController.closePage("session")
        }
        function onSettingsOpenRequested(section): void {
            if (window.presentationTarget) {
                expandedContent.settingsSection = section || "appearance"
                islandController.openPage("settings")
            }
        }
        function onSettingsCloseRequested(): void {
            islandController.closePage("settings")
        }
        function onInsightOpenRequested(page): void {
            if (!window.presentationTarget)
                return
            // "media-center" has no expanded page; it is the media state.
            if (page === "media-center") {
                islandController.openMedia()
                return
            }
            if (page === "battery" && !BatteryService.available)
                islandController.openPage("calendar")
            else
                islandController.openPage(page)
        }
        // Generic bridge for pages that only need plain open/dismiss toggle
        // semantics and don't have a dedicated *ToggleRequested signal of
        // their own (session, overview/dashboard, media-center, settings,
        // wallpaper) -- see core/ShellCompatShortcuts.qml, which is the only
        // current caller.
        function onPageToggleRequested(page): void {
            if (!window.presentationTarget)
                return
            if (page === "media-center")
                islandController.toggleMedia()
            else
                islandController.togglePage(page)
        }
    }

    // core/ShellCompatShortcuts.qml's osdVolumeTrigger equivalent: show the
    // volume OSD without touching the level, e.g. as a standalone "what's my
    // volume" glance. Reuses the exact same presentation path a real volume
    // change takes.
    Connections {
        target: ShellActions
        function onOsdVolumeTriggerRequested(): void {
            if (window.presentationTarget && AudioService.available)
                islandController.showVolume(AudioService.volume, AudioService.muted, AudioService.outputName)
        }
    }

    Connections {
        target: AudioService
        // suppressOsd is true for edge-scroll originated changes
        // (services/AudioService.qml's setVolumeFromEdge) -- edge/
        // VolumeEdge.qml's own gauge is already showing the level right at
        // the cursor, so the island's OSD would just be a duplicate.
        // Media keys and everything else still land here with it false.
        function onOutputLevelChanged(level, muted, deviceName, suppressOsd): void {
            if (window.presentationTarget && !suppressOsd)
                islandController.showVolume(level, muted, deviceName)
        }
        function onMicrophoneLevelChanged(level, muted, deviceName): void {
            if (window.presentationTarget)
                islandController.showMicrophone(level, muted, deviceName)
        }
    }

    Connections {
        target: BrightnessService
        function onBrightnessChanged(level, deviceName): void {
            if (window.presentationTarget)
                islandController.showBrightness(level, deviceName)
        }
    }

    Connections {
        target: PowerProfileService
        function onProfileSelected(level, profileName): void {
            if (window.presentationTarget)
                islandController.showPowerProfile(level, profileName)
        }
    }

    Connections {
        target: BatteryService
        function onPowerConnected(): void {
            if (window.presentationTarget) {
                window.pillPulseColor = Theme.success
                powerConnectedPulse.restart()
                islandController.showBattery(BatteryService.percentageInt / 100)
            }
        }
        function onPowerDisconnected(): void {
            if (window.presentationTarget) {
                window.pillPulseColor = Theme.error
                powerConnectedPulse.restart()
                islandController.showBattery(BatteryService.percentageInt / 100)
            }
        }
        function onPercentageChanged(): void {
            // Low battery (<=20%) while discharging
            if (BatteryService.percentageInt <= 20 && !BatteryService.charging && window.presentationTarget) {
                islandController.showBattery(BatteryService.percentageInt / 100)
            }
        }
    }

    // Pomodoro finished (services/PomodoroService.qml). Only the presentation
    // island shows it, so one timer end is one toast, not one per screen.
    Connections {
        target: PomodoroService
        function onFinished(breakOver: bool): void {
            if (window.presentationTarget)
                islandController.showTimerDone(breakOver)
        }
    }

    Connections {
        target: MediaService
        function onPresentationRequested(): void {
            if (Config.media.enabled && window.presentationTarget)
                islandController.showMedia()
        }
        function onPresentationDismissRequested(): void {
            if (islandController.visualState === islandController.media)
                islandController.clearTransient()
        }
    }

    Connections {
        target: NotificationService
        function onPresentationRequested(critical): void {
            if (window.presentationTarget)
                islandController.showNotification(critical)
        }
        function onPresentationDismissRequested(): void {
            if (islandController.visualState === islandController.notification)
                islandController.expireTransientNotification()
        }
        function onTransientDismissRequested(): void {
            islandController.dismissTransientNotification()
        }
        function onActivationCompleted(): void {
            if (islandController.visualState === islandController.notification)
                islandController.dismissTransientNotification()
            else if (islandController.expandedPage === "notifications")
                islandController.dismiss(true)
        }
    }

    Connections {
        target: islandController
        function onNotificationFinished(): void {
            NotificationService.toastFinished()
        }
    }
}
