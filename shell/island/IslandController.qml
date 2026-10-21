import QtQuick
import "../core"
import "../services"

QtObject {
    id: root

    readonly property string dormant: "dormant"
    readonly property string hover: "hover"
    readonly property string expanded: "expanded"
    readonly property string volume: "volume"
    readonly property string microphone: "microphone"
    readonly property string brightness: "brightness"
    readonly property string powerProfile: "powerProfile"
    readonly property string media: "media"
    readonly property string notification: "notification"
    readonly property string switcher: "switcher"
    // iPhone continuity (services/PhoneService.qml). Only ever requested by
    // events PhoneService emits, so nothing appears while phone.enabled is off.
    readonly property string call: "call"
    readonly property string callActive: "callActive"
    readonly property string phoneMessage: "phoneMessage"
    // AirPlay PIN (47) and the live indicators (34): see syncPhoneLive().
    readonly property string airplayPin: "airplayPin"
    readonly property string mirroring: "mirroring"
    readonly property string camera: "camera"
    // Pomodoro / `timer start` finished: "Focus done" or "Break over". Shares
    // priority 45 with notifications, so it never covers a call.
    readonly property string timerDone: "timerDone"
    // Battery plug/unplug and low-charge OSD (island/Island.qml's BatteryOSD).
    // It is an OSD, so priority 40 like volume, and it never covers a call.
    readonly property string battery: "battery"
    readonly property bool phoneState: transientState === call
        || transientState === callActive || transientState === phoneMessage
        || transientState === airplayPin || transientState === mirroring
        || transientState === camera
    // The newest incoming text shown by the phoneMessage toast.
    property var phoneMessageEntry: null
    property string timerDoneLabel: ""
    property bool timerDoneBreakOver: false
    property real phoneMessageOpenedMs: 0
    // The active-call pill grows into mute / hang up controls when clicked.
    property bool callPillExpanded: false

    property string logicalState: dormant
    property string transientState: ""
    property int transientPriority: 0
    property real transientLevel: 0
    property bool transientMuted: false
    property string transientDeviceName: ""
    property bool pointerInside: false
    // A transient click returns directly to the Auto Hide geometry. This is a
    // state transition, not a delayed/pointer-derived dismissal.
    property bool immediateHiddenTransition: false
    property bool notificationDismissing: false
    signal transientDismissAnimationFinished()
    // The notification popup has fully left the screen, so the next queued
    // toast can be shown without landing inside this exit fade.
    signal notificationFinished()
    property bool mediaVisible: false
    // Set by Island.qml from LyricsService. The resting pill widens by the
    // lyric band (plus its 6 px gap) so the band is revealed by the SAME spring
    // that sizes the island, rather than content overflowing a fixed pill.
    property bool lyricsVisible: false

    // Resting-pill workspace-switch overlay (island/IslandRestItem.qml's
    // clockComponent + island/WorkspacePillRow.qml): the clock cross-fades
    // out and a row of workspace indicators fades in for a beat whenever the
    // focused workspace changes. Tracked here (not inside the rest item
    // itself) because it also needs to widen targetWidth below -- the SAME
    // spring-through-onTargetWidthChanged mechanism lyricsVisible already
    // uses, so the pill's width change is never a separate, unsynced motion.
    // Plain values, NOT bindings: a binding to activeWorkspaceId updates before
    // onContextChanged runs, so the "did it change?" check below never fired.
    property int lastWorkspaceId: 0
    property int previousWorkspaceId: 0

    property bool workspaceSwitchActive: false
    // Shown range is 1..max(highest occupied id, active id), floored at 5 so
    // a nearly-empty desktop still reads as a row, not a single dot.
    readonly property int workspaceIndicatorMax: {
        let highest = root.lastWorkspaceId
        for (const workspace of HyprlandService.occupiedWorkspaces) {
            if ((workspace?.id || 0) > highest)
                highest = workspace.id
        }
        return Math.max(5, highest)
    }
    property Connections workspaceSwitchWatcher: Connections {
        target: HyprlandService
        function onContextChanged(): void {
            const id = HyprlandService.activeWorkspaceId
            if (id > 0 && id !== root.lastWorkspaceId) {
                root.previousWorkspaceId = root.lastWorkspaceId
                root.lastWorkspaceId = id
                // Ink: no icon-row flash on the rest pill. Workspace feedback
                // is the WorkspaceToast only, so this flag (and every width
                // it drives) never flips under ink.
                if (!Config.appearance.ink) {
                    root.workspaceSwitchActive = true
                    workspaceRevertTimer.restart()
                }
            }
        }
    }
    // 1.5s of no further switches reverts to the clock -- see
    // island/WorkspacePillRow.qml's header comment for why this lives on a
    // plain Timer rather than a MotionValue (it's a discrete state flip, not
    // a physical quantity).
    property Timer workspaceRevertTimer: Timer {
        interval: 1500
        onTriggered: root.workspaceSwitchActive = false
    }

    property bool fullscreen: false
    property string expandedPage: "overview"
    // Live pixel height of the control centre's own content (see targetHeight
    // below); 0 on any other page.
    property real controlCenterContentHeight: 0
    property bool dismissing: false
    property string dismissTarget: dormant
    property bool autoHidden: false
    property bool autoHideEnabled: Config.island.autoHide
    property bool overlayWithoutReservation: false
    // Live pixel height of the polkit dialog's own content (see
    // panels/PolkitPage.qml / island/IslandExpanded.qml); 0 on any other page.
    property real polkitContentHeight: 0
    // Live content height of the ink dashboard (see IslandExpanded.qml).
    property real dashboardContentHeight: 0
    // Live content height of the ink calendar page (see IslandExpanded.qml).
    property real calendarContentHeight: 0

    // panels/SessionPage.qml's page is exactly `n` square tiles in a row --
    // no fixed page size fits every machine's session-action availability
    // (e.g. no Hibernate). `n` is read from the same SessionService flags
    // SessionPage.qml itself gates its tiles on, so the two can never
    // disagree. Formula is the proto's calc(var(--h) * k) copied verbatim:
    // island padding (0.44u) + n tiles (2.12u each) + (n-1) gaps (0.22u).
    readonly property int sessionActionCount: [
        SessionService.lockAvailable, SessionService.suspendAvailable,
        SessionService.hibernateAvailable, SessionService.logoutAvailable,
        SessionService.rebootAvailable, SessionService.shutdownAvailable
    ].filter(available => available).length
    readonly property int sessionPageWidth: Theme.u(0.44
        + root.sessionActionCount * 2.12
        + Math.max(0, root.sessionActionCount - 1) * 0.22)

    // Preview-only override (services/PreviewService.qml's `hover` IPC
    // call): forces the hover presentation for screenshotting without a
    // real pointer. Always false, and this read inert, unless
    // QMLRICE_PREVIEW=1 -- PreviewService.hoverForced can only ever be set
    // from behind that same gate.
    readonly property bool previewHoverForced: PreviewService.enabled
        && PreviewService.hoverForced
    // Alt+Tab app switcher (island/IslandSwitcher.qml). It owns the island
    // while open, above every transient and page, and is driven only by the
    // switcher IPC (core/ShellActions.qml) through the functions below.
    property bool switcherOpen: false
    property int switcherIndex: 0
    // Snapshot of RunningApps.groups taken when the switcher opens.
    property var switcherItems: []
    readonly property int switcherMaxVisible: 9
    readonly property int switcherVisibleCount:
        Math.max(1, Math.min(root.switcherItems.length, root.switcherMaxVisible))
    // Row of 56px cells, 12px gaps, 24px side padding, 260px floor (base px,
    // scaled like every other island size). Height 132 is the showcase size.
    readonly property int switcherTargetWidth: Math.round(Math.max(260,
        48 + root.switcherVisibleCount * 56
            + Math.max(0, root.switcherVisibleCount - 1) * 12)
        * DisplayScale.primary)
    readonly property int switcherTargetHeight: Math.round(132 * DisplayScale.primary)

    readonly property string visualState: previewHoverForced ? hover
        : switcherOpen ? switcher
        : (transientState || logicalState)
    readonly property bool transientActive: transientState !== ""
    readonly property bool revealOnly: (autoHidden || fullscreen)
        && visualState === dormant && !pointerInside && !dismissing
    readonly property bool expandedActive: logicalState === expanded && !dismissing
    readonly property bool expandedPresentationActive: logicalState === expanded || dismissing
    // IMPASTO REMOVED (docs/superpowers/specs/2026-09-23-blob-rebuild-
    // design.md section 1 "Removed"): this used to be `cardPageIds`, every
    // one of impasto's 13 module detail cards (island/cards/*.qml, now
    // deleted) plus its notes deck and kanban board, each its own island
    // state, sized via moduleCatalogue/moduleOpenSize/cardModuleIds/
    // cardSize() below (also removed). `overview` now always shows the
    // pre-impasto panels/Dashboard.qml (island/IslandExpanded.qml), sized
    // from the plain Config.dashboard entry below instead of impasto's
    // per-page dashboardPanelSizes/DashBlocksService.panelWidth table.
    readonly property bool dashboardPage: expandedPage === "overview"
    // Subpages DashboardSlim's entry row opens (notes/todo/pet) -- morph
    // the SAME body 0 to BlobLayout's "subpage" size (spec section 6:
    // min(16u, sw-2u) x min(10u, sh*0.7)), not a new island state.
    readonly property bool subpagePage: expandedPage === "notes"
        || expandedPage === "todo" || expandedPage === "pet"

    readonly property bool messagesPage: expandedPage === "messages"
    // Thread the Messages page opens on ("" = most recent).
    property string messagesThreadId: ""
    function openMessages(threadId: string): void {
        messagesThreadId = threadId || ""
        openPage("messages")
    }

    readonly property bool wallpaperPage: expandedPage === "wallpaper"
    readonly property bool clipboardPage: expandedPage === "clipboard"
    readonly property bool sessionPage: expandedPage === "session"
    readonly property bool settingsPage: expandedPage === "settings"
    readonly property bool controlCenterPage: expandedPage === "control-center"
    readonly property bool polkitPage: expandedPage === "polkit"
    // Insight pages (island/Island.qml's onInsightOpenRequested routes the
    // `insights` IPC calendar/weather/system/battery requests here).
    readonly property bool calendarPage: expandedPage === "calendar"
    readonly property bool systemPage: expandedPage === "system"
    readonly property bool batteryPage: expandedPage === "battery"

    // Set from Island.qml (screen: window.screen). Needed to size the
    // dashboard/subpage bodies from the SCREEN, not a fixed Config pixel
    // literal -- see dashboardTargetWidth/Height and
    // subpageTargetWidth/Height below, which mirror panels/DashboardSlim's
    // own dashWidth/dashHeight formula and BlobLayout's "subpage" case
    // respectively so the pill's target size and the content's own layout
    // never disagree.
    property var screen: null
    readonly property real _unit: root.screen ? BlobLayout.unit(root.screen) : 44
    readonly property real dashboardTargetWidth: root.screen
        ? Math.min(root._unit * 18, root.screen.width - root._unit * 2)
        : Config.dashboard.width
    // Ink: the body is the dashboard's real content height plus the
    // expanded host's own margins (the same +space4*2 the control centre and
    // polkit use). Until the first layout reports, it floors at the old
    // 9-unit height so the page never opens as a sliver.
    readonly property real dashboardTargetHeight: root.screen
        ? (Config.appearance.ink
            ? Math.min(root.screen.height, root.dashboardContentHeight > 0
                ? Math.round(root.dashboardContentHeight + Theme.space4 * 2)
                : root._unit * 9)
            : Math.min(root._unit * 9, root.screen.height))
        : Config.dashboard.height
    readonly property real subpageTargetWidth: root.screen
        ? Math.min(root._unit * 16, root.screen.width - root._unit * 2)
        : Config.dashboard.width
    readonly property real subpageTargetHeight: root.screen
        ? Math.min(root._unit * 10, root.screen.height * 0.7)
        : Config.dashboard.height
    readonly property bool shouldShow: !fullscreen || !Config.island.hideInFullscreen
        || transientActive || dismissing
        || Config.island.autoHide || fullscreen

    // impasto: bar/widgets/DynamicIsland.qml's `roomForPanel` (default
    // 100000, i.e. unconstrained without a bar) and
    // `panelWidth: Math.min(panelSize.width, roomForPanel)`. Set from
    // Island.qml to the monitor's real screen.width -- this shell's island
    // floats rather than living inside a bar, so "room" is simply the whole
    // screen, same as impasto gets on a bar-less monitor.
    property int roomForPanel: 100000

    // island/IslandDormant.qml's measured content width, so the resting pill
    // can grow for real content (a wide rest item, the recording timer)
    // without every pill being padded out to a fixed width.
    property real restContentWidth: 0

    // The expanded page's own final width, split out of targetWidth below so
    // island/Island.qml's expanded-content host can size itself from the SAME
    // table instead of keeping a second, drifting copy of it. That copy is
    // what made every impasto card render into a 420/560/620-wide slab while
    // its content was still laid out at the old shared Config.insights.width
    // -- content clipped, panels reading as empty black boxes.
    readonly property int expandedTargetWidth:
        Math.min(root.roomForPanel, (dashboardPage ? root.dashboardTargetWidth
            : subpagePage ? root.subpageTargetWidth
            : expandedPage === "notifications" ? Config.notifications.width
            : messagesPage ? Math.min(Math.round(780 * DisplayScale.primary),
                root.screen ? root.screen.width - root._unit * 2 : 100000)
            : wallpaperPage ? Config.wallpaper.width
            // Calendar + weather, system and battery: showcase widths
            // (screens/calendar-weather.html, system.html).
            : calendarPage ? Math.round(720 * DisplayScale.primary)
            : systemPage ? Math.round(560 * DisplayScale.primary)
            : batteryPage ? Math.round(360 * DisplayScale.primary)
            // Clipboard reuses the launcher's row language and page width --
            // see panels/ClipboardPage.qml / launcher/LauncherView.qml.
            : clipboardPage ? Theme.u(11.67)
            : sessionPage ? root.sessionPageWidth
            : settingsPage ? Config.settings.width
            : expandedPage === "launcher"
                ? Theme.u(11.67)
            : expandedPage === "command-launcher"
                ? Config.launcher.width
            // The control centre is the one page whose width is a Phase A
            // design-unit value, not the general island.expandedWidth
            // setting -- see components/ControlDetailPanel.qml and
            // panels/ControlCenter.qml, which are sized to fit Theme.u(11)
            // exactly. Every other page keeps the user-configurable
            // expandedWidth (Settings -> Appearance) for now.
            : controlCenterPage ? Theme.u(11)
            // The polkit dialog is narrower still -- see panels/PolkitPage.qml.
            : polkitPage ? Theme.u(10)
            : Config.island.expandedWidth))

    // Ink sizes (spec 2026-10-08 P1, showcase island-states.html) are plain
    // px at 1x, scaled like every other island size by DisplayScale.primary.
    readonly property int targetWidth: visualState === switcher
        ? root.switcherTargetWidth
        : visualState === expanded
        ? root.expandedTargetWidth
        : visualState === media
            ? (Config.appearance.ink ? Math.round(560 * DisplayScale.primary) : Config.island.mediaWidth)
        : visualState === notification
            ? (Config.appearance.ink ? Math.round(520 * DisplayScale.primary) : Theme.u(9.44))
        : visualState === call ? Math.round(520 * DisplayScale.primary)
        : visualState === phoneMessage ? Math.round(520 * DisplayScale.primary)
        : visualState === timerDone ? Math.round(260 * DisplayScale.primary)
        : visualState === airplayPin ? Math.round(420 * DisplayScale.primary)
        : (visualState === mirroring || visualState === camera)
            ? Math.round(210 * DisplayScale.primary)
        : visualState === callActive
            ? Math.round((callPillExpanded ? 340 : (PhoneService.call && PhoneService.call.state === "incoming" ? 250 : 190)) * DisplayScale.primary)
        // The level/profile OSD pill -- see island/IslandOSD.qml. Set here,
        // not Config.island.osdWidth/osdHeight, per the Phase C design unit.
        : transientActive
            ? (Config.appearance.ink ? Math.round(340 * DisplayScale.primary) : Theme.u(7.44))
        : visualState === hover
            ? (Config.appearance.ink ? Math.round(Theme.inkHoverW * DisplayScale.primary) : (mediaVisible
                ? Math.max(Config.island.hoverWidth,
                    Config.island.hoverMediaMinimumWidth)
                : Math.max(Config.island.hoverWidth,
                    Config.island.hoverMinimumWidth)))
        : (Config.appearance.ink ? Math.max(Math.round(Theme.inkRestMinW * DisplayScale.primary), root.restContentWidth) : Math.max(Config.island.dormantWidth,
            Config.island.restMinimumWidth,
            root.restContentWidth))
            + (lyricsVisible
                ? Config.media.lyricsBandWidth + Config.media.lyricsBandGap
                : 0)
            + (workspaceSwitchActive
                ? root.workspaceIndicatorMax * Theme.u(0.62)
                    + Math.max(0, root.workspaceIndicatorMax - 1) * Theme.u(0.14)
                : 0)
            // island/RecordingIndicator.qml's own footprint (dot + gap +
            // "00:00" text), duplicated here so the pill widens BEFORE the
            // indicator appears -- see that file's WIDTH CONTRACT comment.
            // Plus restItemSpacing: IslandDormant.qml's right-hand
            // RowLayout only inserts that gap between items that both have
            // nonzero width, and this formula can't see whether the LAST
            // configured rest item is currently showing, so it's always
            // added while recording -- a few extra px of empty padding
            // when it lands right after another rest item, never a
            // clipped one when it doesn't.
            + (ScreenRecService.recording
                ? Config.island.restItemSpacing
                    + Theme.u(0.16) + Theme.u(0.1) + Theme.u(0.72)
                : 0)
            // island/TimerIndicator.qml's footprint (ring + gap + "00:00"),
            // duplicated here for the same reason as the recording term above.
            // Shown while running or paused, so it is always present with it.
            + (PomodoroService.running || PomodoroService.paused
                ? Config.island.restItemSpacing
                    + (Config.appearance.ink ? 12 + 8 + 46
                        : Theme.u(0.2) + Theme.u(0.1) + Theme.u(0.72))
                : 0)
    // Same split as expandedTargetWidth above, for the same reason.
    readonly property int expandedTargetHeight:
        (dashboardPage ? root.dashboardTargetHeight
            : subpagePage ? root.subpageTargetHeight
            : expandedPage === "notifications" ? Config.notifications.height
            : messagesPage ? Math.round(500 * DisplayScale.primary)
            : wallpaperPage ? Config.wallpaper.height
            // Heights are the showcase content heights (calendar: 488 of
            // agenda and grid + 24px padding each side; system: 426). Without
            // ink, the system page's old six-card grid needs a little more.
            : calendarPage
                // Ink: the page fits its own content (agenda and grid plus
                // the 24px padding); glass keeps the old fixed height.
                ? (Config.appearance.ink && root.calendarContentHeight > 0
                    ? Math.round(root.calendarContentHeight + Theme.space4 * 2)
                    : Math.round(536 * DisplayScale.primary))
            : systemPage ? Math.round((Config.appearance.ink ? 426 : 440) * DisplayScale.primary)
            : batteryPage ? Config.island.expandedHeight
            : clipboardPage ? Config.clipboard.height
            // The session page is exactly one row of square tiles -- see
            // root.sessionPageWidth above and panels/SessionPage.qml.
            : sessionPage ? Theme.u(2.6)
            : settingsPage ? Config.settings.height
            : (expandedPage === "launcher" || expandedPage === "command-launcher")
                ? Config.launcher.height
            : expandedPage === "control-center"
                // The control centre's own content decides its height -- tile
                // grid, sliders, the media card (which may itself be mid-spring
                // into its lyrics-expanded height) and up to 3 notifications --
                // rather than a single fixed page size. controlCenterContentHeight
                // is IslandExpanded's live implicitHeight passthrough, so this
                // is a spring chasing a continuously moving target, same as the
                // surface's own geometry springs below it.
                ? Math.round(Math.max(Config.island.expandedHeight,
                    controlCenterContentHeight + Theme.space4 * 2))
                // Same "chase the real content height" mechanism as the
                // control centre, just for panels/PolkitPage.qml's much
                // smaller dialog -- it still floors at expandedHeight so a
                // one-line prompt doesn't render as a sliver.
                : expandedPage === "polkit"
                    ? Math.round(Math.max(Config.island.expandedHeight,
                        polkitContentHeight + Theme.space4 * 2))
                : Config.island.expandedHeight)

    readonly property int targetHeight: visualState === switcher
        ? root.switcherTargetHeight
        : visualState === expanded
        ? root.expandedTargetHeight
        : visualState === media
            ? (Config.appearance.ink ? Math.round(232 * DisplayScale.primary) : Config.island.mediaHeight)
        : visualState === notification
            ? (Config.appearance.ink ? Math.round(88 * DisplayScale.primary) : Theme.u(2.1))
        : visualState === call ? Math.round(104 * DisplayScale.primary)
        : visualState === phoneMessage ? Math.round(132 * DisplayScale.primary)
        : visualState === timerDone ? Math.round(56 * DisplayScale.primary)
        : visualState === airplayPin ? Math.round(104 * DisplayScale.primary)
        : (visualState === mirroring || visualState === camera)
            ? Math.round(44 * DisplayScale.primary)
        : visualState === callActive
            ? Math.round((callPillExpanded ? 76 : 44) * DisplayScale.primary)
        : transientActive
            ? (Config.appearance.ink ? Math.round(56 * DisplayScale.primary) : Theme.u(1.2))
        : visualState === hover
            ? (Config.appearance.ink ? Math.round(Theme.inkHoverH * DisplayScale.primary) : Config.island.hoverHeight)
        : (Config.appearance.ink ? Math.round(Theme.inkRestH * DisplayScale.primary) : Config.island.dormantHeight)

    // Alt+Tab. Opening from rest selects the previous app (index 1), or the
    // least recent one for a reverse step. Once open, a step moves the
    // selection with wrap-around; the focused window stays at index 0.
    function openSwitcher(step: int): void {
        const groups = RunningApps.groups
        if (groups.length === 0)
            return
        collapseTimer.stop()
        clearTransient()
        cancelDismissal()
        // The switcher supersedes a page or a hover. Returning to rest on
        // close keeps the surface from snapping back to a stale page.
        if (logicalState !== dormant)
            logicalState = dormant
        switcherItems = groups
        switcherIndex = groups.length >= 2
            ? (step < 0 ? groups.length - 1 : 1) : 0
        showSurface()
        switcherOpen = true
    }

    function stepSwitcher(step: int): void {
        if (!switcherOpen) {
            openSwitcher(step)
            return
        }
        const count = switcherItems.length
        if (count > 0)
            switcherIndex = (switcherIndex + step + count) % count
    }

    function closeSwitcher(): void {
        if (!switcherOpen)
            return
        // switcherItems is kept so the content can fade out with its labels.
        // The next open replaces it.
        switcherOpen = false
    }

    function commitSwitcher(): void {
        if (!switcherOpen)
            return
        const group = switcherItems[switcherIndex] || null
        closeSwitcher()
        if (group)
            RunningApps.focus(group)
    }

    function commitSwitcherAt(index: int): void {
        if (!switcherOpen || index < 0 || index >= switcherItems.length)
            return
        switcherIndex = index
        commitSwitcher()
    }

    function statePriority(state): int {
        if (state === expanded)
            return 50
        if (state === call)
            return 48
        if (state === airplayPin)
            return 47
        if (state === notification || state === phoneMessage || state === timerDone)
            return 45
        if (state === volume || state === microphone || state === brightness
                || state === powerProfile || state === battery)
            return 40
        if (state === callActive)
            return 35
        if (state === mirroring || state === camera)
            return 34
        if (state === media)
            return 30
        if (state === hover)
            return 20
        return 0
    }

    function enter(): void {
        collapseTimer.stop()
        pointerInside = true
        immediateHiddenTransition = false
        // Notification/transient overlays must remain outside the workspace
        // reservation when hovered. Only the hidden resting edge deliberately
        // converts a pointer reveal back into a workspace-reserving surface.
        showSurface(autoHidden || !overlayWithoutReservation)
        if (dismissing)
            return
        if (!expandedActive)
            logicalState = hover
    }

    function leave(): void {
        pointerInside = false
        if (!dismissing && logicalState === hover)
            collapseTimer.restart()
    }

    function cancelDismissal(): void {
        dismissSurfaceTimer.stop()
        dismissing = false
    }

    function showSurface(reserveWorkspace): void {
        autoHideTimer.stop()
        immediateHiddenTransition = false
        autoHidden = false
        overlayWithoutReservation = autoHideEnabled
            && reserveWorkspace === false
    }

    function scheduleAutoHide(): void {
        autoHideTimer.stop()
        if (autoHideEnabled && visualState === dormant && !pointerInside
                && !dismissing)
            autoHideTimer.restart()
    }

    function deactivateForMonitorPolicy(): void {
        collapseTimer.stop()
        dismissSurfaceTimer.stop()
        transientTimer.stop()
        transientState = ""
        transientPriority = 0
        switcherOpen = false
        pointerInside = false
        dismissing = false
        expandedPage = "overview"
        logicalState = dormant
        showSurface()
    }

    // Set by openPage() below. The pill's whole-surface TapHandler (island/
    // Island.qml) and the content's own per-item TapHandlers BOTH receive
    // the same click: the item handler opens its page, then the surface
    // handler toggles -- sees an open island -- and dismisses it in the same
    // event. That is the "I have to click twice" behaviour. A toggle that
    // lands within one event of a deliberate open is that echo, never a
    // second press by hand.
    property real lastOpenMs: 0

    function toggleExpanded(): void {
        if (expandedActive && Date.now() - root.lastOpenMs < 350)
            return
        showSurface()
        const openNotificationCenter = visualState === notification
        collapseTimer.stop()
        clearTransient()
        if (expandedActive)
            dismiss()
        else {
            cancelDismissal()
            expandedPage = openNotificationCenter ? "notifications" : "overview"
            logicalState = expanded
        }
    }

    // Mac style guard (spec 2026-10-19-mac-style-design.md section 2): the
    // notification centre and the launcher are Tahoe surfaces (mac/), and so
    // is the Control Center. "overview" is the page controlCenterToggle and
    // the control-center IPC open (Island.qml), so those requests go to the
    // "controlCenter" surface. Returns true when the request was handed to
    // mac; false otherwise (always false in pill style, so pill behaviour is
    // unchanged).
    readonly property var macRoutedSurfaces: ({
        "notifications": "notifications",
        "launcher": "launcher",
        "overview": "controlCenter"
    })
    function macRoute(page: string, action: string): bool {
        const surface = macRoutedSurfaces[page]
        if (!Config.appearance.macStyle || surface === undefined)
            return false
        ShellActions.macSurfaceRequested(surface, action)
        return true
    }

    function openPage(page: string): void {
        if (macRoute(page, "open"))
            return
        root.lastOpenMs = Date.now()
        showSurface()
        collapseTimer.stop()
        clearTransient()
        cancelDismissal()
        expandedPage = page
        logicalState = expanded
    }

    function closePage(page: string): void {
        if (macRoute(page, "close"))   // mac guard, see macRoute()
            return
        if (expandedActive && expandedPage === page)
            dismiss()
    }

    function togglePage(page: string): void {
        if (macRoute(page, "toggle"))  // mac guard, see macRoute()
            return
        // Kept on purpose: the launcher once wedged (taps toggled an invisible page); this records the state if it recurs.
        console.log("IslandController.togglePage " + page + " active=" + expandedActive + " page=" + expandedPage + " state=" + logicalState + " dismissing=" + dismissing)
        if (expandedActive && expandedPage === page)
            dismiss()
        else
            openPage(page)
    }

    function collapse(): void {
        if (dismissing || logicalState !== hover)
            return
        logicalState = pointerInside ? hover : dormant
    }

    function dismiss(forceDormant): void {
        if (dismissing || logicalState !== expanded)
            return
        clearTransient()
        collapseTimer.stop()
        dismissTarget = forceDormant ? dormant
            : (pointerInside ? hover : dormant)
        dismissing = true
        // logicalState flips to the resting target IMMEDIATELY, not after a
        // separate content-fade phase: the outgoing expanded content's own
        // opacity fade (its Behavior, gated on `dismissing` alone --
        // island/Island.qml), the incoming resting content's fade-in, and
        // the geometry morph (island/Island.qml's surface.morphT, driven by
        // this same targetWidth/targetHeight change) all start on the same
        // tick and run CONCURRENTLY. `dismissing` stays true for the
        // duration of the exit morph purely to keep the outgoing expanded
        // content visible/fading (expandedPresentationActive) and to gate
        // re-open semantics -- it no longer gates when the resting content
        // is allowed to appear.
        logicalState = dismissTarget
        dismissSurfaceTimer.restart()
    }

    function settle(): void {
        if (pointerInside || expandedActive)
            return
        logicalState = dormant
    }

    function requestTransient(state, level, muted, deviceName, priority,
            duration, reserveWorkspace): void {
        if (priority < statePriority(logicalState) || priority < transientPriority)
            return

        const directTransientOverlay = autoHideEnabled
            && reserveWorkspace === false
        // A non-reserving transient is an overlay, not a brief restoration of
        // the hidden resting island. Set its state before revealing the surface
        // so the dormant presentation never participates in this transition.
        if (directTransientOverlay)
            overlayWithoutReservation = true
        else
            showSurface(reserveWorkspace)
        transientState = state
        transientLevel = Math.max(0, Math.min(1, level))
        transientMuted = muted
        transientDeviceName = deviceName
        transientPriority = priority
        if (state === call || state === callActive || state === phoneMessage
                || state === airplayPin || state === mirroring || state === camera) {
            // call/callActive persist until PhoneService says otherwise;
            // island/PhoneMessageToast.qml owns its own pausable countdown.
            transientTimer.stop()
        } else if (state === notification) {
            // island/IslandNotification.qml owns a single NumberAnimation on
            // `progress` that IS the countdown for this kind -- its
            // onFinished calls expireTransientNotification() itself. Leaving
            // this generic timer running with the same duration would race
            // it to a second, possibly-earlier dismissal (the exact "two
            // clocks" bug this file used to have). OSD/media transients are
            // untouched -- they still expire from this timer below.
            transientTimer.stop()
        } else {
            transientTimer.interval = duration
            transientTimer.restart()
        }
        if (directTransientOverlay)
            showSurface(reserveWorkspace)
    }

    function showVolume(level, muted, deviceName): void {
        requestTransient(volume, level, muted, deviceName, 40,
            Config.island.osdTimeout, false)
    }

    function showMicrophone(level, muted, deviceName): void {
        requestTransient(microphone, level, muted, deviceName, 40,
            Config.island.osdTimeout, false)
    }

    function showBrightness(level, deviceName): void {
        requestTransient(brightness, level, false, deviceName, 40,
            Config.island.osdTimeout, false)
    }

    function showPowerProfile(level, profileName): void {
        requestTransient(powerProfile, level, false, profileName, 40,
            Config.island.osdTimeout, false)
    }

    function showBattery(level): void {
        requestTransient(battery, level, false, "", 40,
            Config.island.osdTimeout, false)
    }

    function showMedia(): void {
        requestTransient(media, 0, false, "", 30,
            Config.media.presentationTimeout, false)
    }

    // Media "page" (the insights/media-center and mediaControlsToggle entry
    // points). There is no media page in IslandExpanded: the media face is
    // the transient `media` state above, so every entry point routes here
    // instead of openPage("media-center") -- which hosted nothing and showed
    // an empty expanded page. An open page wins over a transient (its
    // statePriority is 50), so it is dismissed first.
    function openMedia(): void {
        if (!Config.media.enabled)
            return
        if (expandedActive)
            dismiss(true)
        showMedia()
    }

    function toggleMedia(): void {
        if (visualState === media) {
            clearTransient()
            return
        }
        openMedia()
    }

    // Fired by the pomodoro finish signal (island/Island.qml). A call, an
    // expanded page or a higher-priority OSD wins, so the toast can be dropped.
    function showTimerDone(breakOver: bool): void {
        timerDoneBreakOver = breakOver
        timerDoneLabel = breakOver ? "Break over" : "Focus done"
        requestTransient(timerDone, 0, false, "", 45,
            Config.notifications.timeout, false)
    }

    function showNotification(critical: bool): void {
        // Mac guard: in mac style the banner is a Tahoe surface (mac/
        // MacBanners.qml) that listens to NotificationService directly. The
        // pill presents nothing here. The queue still advances through
        // NotificationService's fallback toastTimer.
        if (Config.appearance.macStyle)
            return
        requestTransient(notification, 0, false, "", critical ? 70 : 45,
            critical ? Config.notifications.criticalTimeout
                : Config.notifications.timeout, false)
    }

    function clearTransient(): void {
        const returnDirectlyToAutoHide = autoHideEnabled
            && overlayWithoutReservation && transientState !== ""
            && !pointerInside && !dismissing
        transientTimer.stop()
        if (returnDirectlyToAutoHide) {
            immediateHiddenTransition = true
            autoHidden = true
        }
        if (transientState === notification && PreviewService.notificationPreviewing)
            PreviewService.clearNotification()
        transientState = ""
        transientPriority = 0
        callPillExpanded = false
        scheduleAutoHide()
        // A call outranks the things that interrupted it (OSD, media, a
        // text toast): bring its state back once they are gone.
        Qt.callLater(syncPhoneCall)
        Qt.callLater(syncPhoneLive)
    }

    // --- iPhone continuity ----------------------------------------------
    // Drives the call / callActive transient from PhoneService.call. The call
    // card leaves as soon as PhoneService.call becomes null (call ended or
    // the phone disconnected), so the island can never stick at priority 48.
    function syncPhoneCall(): void {
        const c = PhoneService.call
        // Attention gate (services/PhoneAttention.qml): quiet while locked.
        // Otherwise a ringing call always gets the card, idle or not: the
        // pill is only for a call that was answered (the idle gate would
        // otherwise turn a ring into a timer pill nobody can act on).
        const gate = PhoneAttention.decide("call", PhoneAttention.idle, PhoneAttention.locked)
        const want = !c || gate === "quiet" ? ""
            // Mac guard: a ringing call goes to mac/MacCallBanner.qml, not the
            // pill card. An answered call (callActive) always stays in the pill.
            : c.state === "incoming" ? (Config.appearance.macStyle ? "" : call)
            : callActive
        if (want === "") {
            if (transientState === call || transientState === callActive)
                clearTransient()
            return
        }
        if (transientState === want)
            return
        if (transientState === call || transientState === callActive)
            clearTransient()
        requestTransient(want, 0, false, "", want === call ? 48 : 35, 0, false)
    }

    // AirPlay PIN + live indicators from PhoneService. The PIN leaves as soon
    // as airplayState changes. Mirroring (or AirPlay audio) wins over camera;
    // the pill shows a second dot when both are live. These are independent
    // of Bluetooth, so they do not depend on PhoneService.connected.
    // Gated by PhoneAttention: the PIN only while at the machine, the live
    // indicators unless locked.
    readonly property string phoneLiveWant: PhoneService.airplayState === "pin"
            ? (PhoneAttention.decide("pin", PhoneAttention.idle, PhoneAttention.locked) === "show" ? airplayPin : "")
        : PhoneAttention.decide("live", PhoneAttention.idle, PhoneAttention.locked) !== "show" ? ""
        : (PhoneService.airplayState === "mirroring" || PhoneService.airplayState === "audio") ? mirroring
        : PhoneService.cameraActive ? camera
        : ""
    function syncPhoneLive(): void {
        const want = phoneLiveWant
        const mine = transientState === airplayPin || transientState === mirroring
            || transientState === camera
        if (want === "") {
            if (mine)
                clearTransient()
            return
        }
        if (transientState === want)
            return
        if (mine)
            clearTransient()
        requestTransient(want, 0, false, "", want === airplayPin ? 47 : 34, 0, false)
    }
    onPhoneLiveWantChanged: syncPhoneLive()

    function showPhoneMessage(msg): void {
        // Quiet (idle or locked): PhoneService.recentMessages already has it.
        if (PhoneAttention.decide("message", PhoneAttention.idle, PhoneAttention.locked) !== "show")
            return
        phoneMessageEntry = msg
        phoneMessageOpenedMs = Date.now()
        requestTransient(phoneMessage, 0, false, "", 45,
            Config.notifications.timeout, false)
    }

    // Re-evaluate when this machine becomes active/idle/locked: a call still
    // ringing gets its card when the user returns; a toast never outlives a lock.
    property Connections attentionLink: Connections {
        target: PhoneAttention
        function onIdleChanged(): void { root._phoneAttentionChanged() }
        function onLockedChanged(): void { root._phoneAttentionChanged() }
    }
    function _phoneAttentionChanged(): void {
        if (PhoneAttention.locked && transientState === phoneMessage) {
            phoneMessageEntry = null
            clearTransient()
        }
        syncPhoneCall()
        syncPhoneLive()
    }

    property Connections phoneLink: Connections {
        target: PhoneService
        function onCallChanged(): void { root.syncPhoneCall() }
        function onMessageReceived(msg): void {
            if (msg && !msg.outgoing)
                root.showPhoneMessage(msg)
        }
    }

    function expireTransientNotification(): void {
        // Use the same visual dismissal phase as a click. It keeps the overlay
        // alive for the existing reverse opacity transition, then resolves
        // directly to hidden without exposing the resting island.
        if (notificationDismissing)
            return
        if (visualState !== notification) {
            clearTransient()
            return
        }
        dismissTransientNotification()
    }

    function dismissTransientNotification(): void {
        if (visualState !== notification || notificationDismissing)
            return
        notificationDismissing = true
        notificationDismissTimer.restart()
    }

    function finishTransientNotificationDismiss(): void {
        notificationDismissing = false
        collapseTimer.stop()
        logicalState = dormant
        if (autoHideEnabled) {
            // A click originated inside the temporary overlay, not the resting
            // Island. Restore the hidden state synchronously instead of waiting
            // for a pointer-leave event that may happen after focus changes.
            pointerInside = false
            immediateHiddenTransition = true
            autoHidden = true
        }
        clearTransient()
        transientDismissAnimationFinished()
        notificationFinished()
    }

    onVisualStateChanged: {
        if (visualState === dormant)
            scheduleAutoHide()
        else
            showSurface(!overlayWithoutReservation)
    }

    onAutoHideEnabledChanged: {
        if (autoHideEnabled)
            scheduleAutoHide()
        else {
            immediateHiddenTransition = false
            showSurface()
        }
    }

    property Timer collapseTimer: Timer {
        interval: Config.island.collapseDelay
        onTriggered: root.collapse()
    }

    // Preview IPC (services/PreviewService.qml, QMLRICE_PREVIEW=1 only):
    // shows the OSD/notification popup with FAKE data through the exact same
    // presentation path a real one takes -- these show*() calls never touch
    // PipeWire/backlight/D-Bus themselves, they only ever set the properties
    // above.
    property Connections previewLink: Connections {
        target: PreviewService
        enabled: PreviewService.enabled

        function onOsdRequested(): void {
            const kind = PreviewService.osdKind
            const percent = PreviewService.osdPercent
            if (kind === "microphone")
                root.showMicrophone(percent, false, "Preview")
            else if (kind === "brightness")
                root.showBrightness(percent, "Preview")
            else if (kind === "powerProfile")
                root.showPowerProfile(percent, "Preview")
            else
                root.showVolume(percent, false, "Preview")
        }

        function onNotificationRequested(): void {
            root.showNotification(PreviewService.notificationEntry?.critical ?? false)
        }

        function onMediaRequested(): void {
            root.showMedia()
        }
    }

    property Timer notificationDismissTimer: Timer {
        interval: Animations.fast
        repeat: false
        onTriggered: root.finishTransientNotificationDismiss()
    }

    property Timer dismissSurfaceTimer: Timer {
        interval: Config.animations.surfaceMorph
        onTriggered: {
            root.dismissing = false
            Qt.callLater(root.syncPhoneCall)
            // Pointer state can change while the expanded surface shrinks.
            // Never retain hover when the pointer is outside its final geometry.
            if (root.logicalState === root.hover && !root.pointerInside)
                root.logicalState = root.dormant
            root.scheduleAutoHide()
        }
    }

    property Timer transientTimer: Timer {
        interval: Config.island.osdTimeout
        onTriggered: {
            if (root.transientState === root.notification)
                root.expireTransientNotification()
            else
                root.clearTransient()
        }
    }

    property Timer autoHideTimer: Timer {
        interval: Config.island.autoHideDelay
        onTriggered: {
            if (root.autoHideEnabled && root.visualState === root.dormant
                    && !root.pointerInside && !root.dismissing)
                root.autoHidden = true
        }
    }

    Component.onCompleted: {
        root.lastWorkspaceId = HyprlandService.activeWorkspaceId
        root.previousWorkspaceId = HyprlandService.activeWorkspaceId
        settle()
        scheduleAutoHide()
    }
}
