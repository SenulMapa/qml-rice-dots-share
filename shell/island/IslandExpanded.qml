import QtQuick
import QtQuick.Layouts
import Quickshell.Services.SystemTray
import "../components"
import "../core"
import "../panels"
import "../launcher"
import "../services"

Item {
    id: root
    property var monitor
    // The real Quickshell Screen (island/Island.qml sets this to
    // window.screen) -- DashboardSlim/NotesPage/TodoPage/PetPage size
    // themselves off the SCREEN's own width/height (BlobLayout's unit
    // formula), not this Item's own width/height, which IS already the
    // clamped dashboard/subpage size computed from the screen -- passing
    // that back in as "available" space would double-apply the margin.
    property var screen: null
    property string page: "overview"
    // Ink shared-element tags from the dashboard (island/SharedElements.qml).
    readonly property var shareItems: dashboardSlim.shareItems
    property bool active: false
    property alias settingsSection: settingsPage.section
    readonly property bool overviewOpen: page === "overview"
    readonly property bool launcherOpen: page === "launcher"
    readonly property bool commandLauncherOpen: page === "command-launcher"
    readonly property bool notificationsOpen: page === "notifications"
    readonly property bool clipboardOpen: page === "clipboard"
    readonly property bool sessionOpen: page === "session"
    readonly property bool settingsOpen: page === "settings"
    readonly property bool settingsLivePreviewActive: active && settingsOpen
        && settingsPage.livePreviewActive
    readonly property string settingsPreviewMode: settingsPage.pillPreviewMode
    readonly property bool controlCenterOpen: page === "control-center"
    readonly property bool wallpaperOpen: page === "wallpaper"
    readonly property bool polkitOpen: page === "polkit"
    readonly property bool calendarOpen: page === "calendar"
    readonly property bool systemOpen: page === "system"
    readonly property bool batteryOpen: page === "battery"
    readonly property bool messagesOpen: page === "messages"
    // Thread the Messages page opens on (set by island/Island.qml from
    // IslandController.messagesThreadId).
    property string messagesThreadId: ""
    property alias controlCenter: controlCenter
    // Live pixel height of the control centre's own content, passed through
    // to island/IslandController.qml so the surface can size itself to it.
    // 0 on any other page.
    readonly property real controlCenterContentHeight:
        controlCenterOpen ? controlCenter.contentHeight : 0
    // Same passthrough for the polkit dialog -- see panels/PolkitPage.qml
    // and island/IslandController.qml's `polkitPage` branch.
    readonly property real polkitContentHeight:
        polkitOpen ? polkitPage.contentHeight : 0
    // Ink dashboard: DashboardSlim's own content height (margins included),
    // so the dashboard body fits its content. 0 on any other page.
    readonly property real dashboardContentHeight:
        overviewOpen ? dashboardSlim.contentHeight : 0
    // Ink calendar page: CalendarWeatherPage's own content height. 0 elsewhere.
    readonly property real calendarContentHeight:
        calendarOpen ? calendarPage.contentHeight : 0
    // ---- Wi-Fi / Bluetooth / Audio / tray satellite state ----
    // Owned HERE (not by ControlCenter/panels/ControlCenter.qml, which is
    // deprecated -- see HANDOVER.md) so the satellites work from the
    // overview/dashboard page, not just the old control-center page. The
    // actual open/close/toggle bookkeeping is a pure state machine
    // (components/SatelliteState.qml, unit tested in test-satellite-state
    // .qml); this Item only adds the service side effects (scanning) and
    // the tray-item lookup.
    property SatelliteState satelliteState: SatelliteState {}
    readonly property bool wifiSatelliteVisible: satelliteState.wifiOpen
    readonly property bool bluetoothSatelliteVisible: satelliteState.rightSection === "bluetooth"
    readonly property bool audioSatelliteVisible: satelliteState.rightSection === "audio"
    readonly property bool traySatelliteVisible: satelliteState.rightSection === "tray"
    readonly property bool phoneSatelliteVisible: satelliteState.rightSection === "phone"
    readonly property var traySatelliteItem: satelliteState.rightSection === "tray"
        ? (SystemTray.items.values.find(it => it.id === satelliteState.trayId) ?? null)
        : null

    function openSatellite(section: string): void {
        closeSubviewsFor(section)
        satelliteState.open(section)
    }

    function closeSatellite(): void {
        controlCenter.clearWifiCredentials()
        controlCenter.clearInformationView("wifi")
        controlCenter.clearInformationView("bluetooth")
        satelliteState.closeAll()
    }

    function toggleSatellite(section: string): void {
        closeSubviewsFor(section)
        satelliteState.toggle(section)
    }

    // Clears whichever satellite's OWN wifi-credential/information subview
    // is open before that satellite's section changes -- mirrors what
    // panels/ControlCenter.qml's closeWifiSatellite()/closeBluetoothSatellite()
    // used to do inline.
    function closeSubviewsFor(section: string): void {
        if (section === "wifi") {
            controlCenter.clearWifiCredentials()
            controlCenter.clearInformationView("wifi")
        } else {
            controlCenter.clearInformationView("bluetooth")
        }
    }

    onWifiSatelliteVisibleChanged: NetworkService.setScanning(wifiSatelliteVisible)
    onBluetoothSatelliteVisibleChanged: BluetoothService.setDiscovering(bluetoothSatelliteVisible)

    signal pageSelected(string selectedPage)
    signal dismissRequested(bool forceDormant)

    // Staggered fade-in (components/Reveal.qml): bumped on open or a page
    // change, and ONLY then -- never on a data update, which is exactly
    // why nothing here reacts to anything else. `revealExiting` drives the
    // fast, synchronized close fade instead; it is a plain binding on
    // `active` rather than something set imperatively, so a Reveal that
    // reads it during the SAME tick `active` flips already sees the right
    // value before deciding whether a token bump means "enter" or "ignore".
    property int revealToken: 0
    readonly property bool revealExiting: !active

    function closeTransientUi(): bool {
        if (sessionOpen && sessionPage.cancelConfirmation())
            return true
        // Escape closes a satellite's own subview first, then the
        // satellite(s), then falls through to the island dismiss --
        // matches Escape closing a satellite before the island itself.
        if (controlCenter.closeAnySubview())
            return true
        if (satelliteState.anyOpen) {
            closeSatellite()
            return true
        }
        if (controlCenterOpen)
            return controlCenter.closeExpandedSection()
        // A subpage (notes/todo/pet) steps back to the dashboard, same
        // "one level at a time" idea as satellites above -- Escape never
        // closes the whole island out from under a subpage in one press.
        if (root.page === "notes" || root.page === "todo" || root.page === "pet") {
            root.pageSelected("overview")
            return true
        }
        return false
    }

    onActiveChanged: {
        if (active) {
            inactiveCleanup.stop()
            revealToken++
        } else {
            inactiveCleanup.restart()
            settingsPage.islandEditor = "overview"
        }
    }
    // Switching pages while already open replays the reveal for whatever
    // just became visible. A page change while CLOSED (e.g. something
    // pre-selects a page before the island opens) needs no bump here --
    // the open transition above will bump it once active becomes true.
    onPageChanged: if (active) revealToken++

    Timer {
        id: inactiveCleanup
        interval: Config.animations.surfaceMorph + Animations.fast
        onTriggered: {
            controlCenter.resetDetails()
            closeSatellite()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.space4
        spacing: Theme.space3

        // Every page below gets at least a whole-page fade on open/page
        // change (order 0 -- there is nothing else on the page to stagger
        // against). Dashboard is the exception: it gets the Reveal token
        // and exiting flag directly instead of a wrapper, because it drives
        // its OWN per-element staggered reveal internally.
        //
        // Each page keeps its ORIGINAL `visible: root.xxxOpen` binding on
        // the real component, not just the wrapper -- panels/PolkitPage.qml
        // in particular relies on its own visibleChanged firing (clearing
        // the field, focusing/unfocusing) for the fail-closed cancel path,
        // and a Reveal fading its container to opacity 0 must never be the
        // thing that ends up deciding whether that page is "visible".

        Reveal {
            token: root.revealToken
            exiting: root.revealExiting
            order: 0
            visible: root.notificationsOpen
            Layout.fillWidth: true
            Layout.fillHeight: true
            NotificationCenter {
                anchors.fill: parent
                visible: root.notificationsOpen
            }
        }

        Reveal {
            token: root.revealToken
            exiting: root.revealExiting
            order: 0
            visible: root.clipboardOpen
            Layout.fillWidth: true
            Layout.fillHeight: true
            ClipboardPage {
                anchors.fill: parent
                visible: root.clipboardOpen
            }
        }

        Reveal {
            token: root.revealToken
            exiting: root.revealExiting
            order: 0
            visible: root.sessionOpen
            Layout.fillWidth: true
            Layout.fillHeight: true
            SessionPage {
                id: sessionPage
                anchors.fill: parent
                visible: root.sessionOpen
                onDismissRequested: root.dismissRequested(false)
            }
        }

        Reveal {
            token: root.revealToken
            exiting: root.revealExiting
            order: 0
            visible: root.settingsOpen
            Layout.fillWidth: true
            Layout.fillHeight: true
            SettingsPage {
                id: settingsPage
                anchors.fill: parent
                visible: root.settingsOpen
                monitor: root.monitor
            }
        }

        // IMPASTO REMOVED (docs/superpowers/specs/2026-09-23-blob-rebuild-
        // design.md section 1 "Removed"): this used to route between
        // panels/Dashboard.qml and the impasto-ported dashboard/
        // DashDashboard.qml (DashBlocksService block grid) on
        // DeskSettings.dashboardImpasto. Now the blob's own compact
        // dashboard (panels/DashboardSlim.qml) -- pre-impasto
        // panels/Dashboard.qml is no longer routed here (still in the tree,
        // unreferenced, same "not worth deleting a whole page" call as
        // InsightCenter above).
        //
        // FIX (owner: "going back from workspace view to pill: 0
        // animation"): this used to be a bare `DashboardSlim { visible:
        // root.overviewOpen }` with NO Reveal wrapper at all -- despite the
        // comment two lines up once claiming "Dashboard is the exception:
        // it gets the Reveal token and exiting flag directly... because it
        // drives its OWN per-element staggered reveal internally",
        // DashboardSlim.qml never referenced Reveal/revealToken anywhere.
        // Every page switch into or out of the dashboard (and the subpages
        // below) was a hard visible-flip: literally zero animation. Now
        // wrapped exactly like every other page above.
        //
        // (4 Oct 2026, perf pass) `visible` is gated on `root.active` too.
        // Island.qml hides the expanded content with `opacity:
        // islandController.expandedActive ? 1 : 0` and never flips
        // `visible`, and `page` defaults to "overview", so a collapsed
        // island still had DashboardSlim visible=true -> its continuous
        // work (then VinylDisc's FrameAnimation + Canvas at 60fps; in the
        // glass DashboardSlim, LyricWheel's FrameAnimation and the 1 Hz
        // footer clock, both `running: visible`) ran forever. Opacity is
        // not visibility; same class of bug as BatteryOSD's fadeOpacity gate.
        Reveal {
            token: root.revealToken
            exiting: root.revealExiting
            order: 0
            visible: root.overviewOpen && root.active
            Layout.fillWidth: true
            Layout.fillHeight: true
            DashboardSlim {
                id: dashboardSlim
                anchors.fill: parent
                visible: root.overviewOpen && root.active
                availableWidth: root.screen ? root.screen.width : root.width
                availableHeight: root.screen ? root.screen.height : root.height
                onPageRequested: page => root.pageSelected(page)
                onSatelliteRequested: section => root.toggleSatellite(section)
            }
        }

        // Subpages (docs/superpowers/specs/2026-09-23-blob-rebuild-
        // design.md section 6): DashboardSlim's Notes/Todo/Pet entry row
        // morphs body 0 to BlobLayout's "subpage" size (island/
        // IslandController.qml's subpagePage/subpageTargetWidth/Height) and
        // shows one of these. Always instantiated (visible-gated, not a
        // Loader) so morphing INTO a subpage never activates one mid-
        // motion. back() (or Esc, handled by island/Island.qml's
        // closeTransientUi() -> here, or a click outside) returns to the
        // dashboard, not a full island dismiss. Same Reveal wrapping as
        // every other page (see the dashboard fix above) -- these three
        // were bare `visible:` flips too.
        Reveal {
            token: root.revealToken
            exiting: root.revealExiting
            order: 0
            visible: root.page === "notes"
            Layout.fillWidth: true
            Layout.fillHeight: true
            NotesPage {
                anchors.fill: parent
                visible: root.page === "notes"
                availableWidth: root.screen ? root.screen.width : root.width
                availableHeight: root.screen ? root.screen.height : root.height
                onBack: root.pageSelected("overview")
            }
        }
        Reveal {
            token: root.revealToken
            exiting: root.revealExiting
            order: 0
            visible: root.page === "todo"
            Layout.fillWidth: true
            Layout.fillHeight: true
            TodoPage {
                anchors.fill: parent
                visible: root.page === "todo"
                availableWidth: root.screen ? root.screen.width : root.width
                availableHeight: root.screen ? root.screen.height : root.height
                onBack: root.pageSelected("overview")
            }
        }
        Reveal {
            token: root.revealToken
            exiting: root.revealExiting
            order: 0
            visible: root.page === "pet"
            Layout.fillWidth: true
            Layout.fillHeight: true
            PetPage {
                anchors.fill: parent
                visible: root.page === "pet"
                availableWidth: root.screen ? root.screen.width : root.width
                availableHeight: root.screen ? root.screen.height : root.height
                onBack: root.pageSelected("overview")
            }
        }

        Reveal {
            token: root.revealToken
            exiting: root.revealExiting
            order: 0
            visible: root.messagesOpen
            Layout.fillWidth: true
            Layout.fillHeight: true
            MessagesPage {
                id: messagesPage
                anchors.fill: parent
                active: root.messagesOpen && root.active && PhoneAttention.textAllowed
                visible: root.messagesOpen && PhoneAttention.textAllowed
                onActiveChanged: if (active) threadId = root.messagesThreadId
                Connections {
                    target: root
                    function onMessagesThreadIdChanged(): void {
                        if (root.messagesThreadId !== "")
                            messagesPage.threadId = root.messagesThreadId
                    }
                }
            }
        }

        Reveal {
            token: root.revealToken
            exiting: root.revealExiting
            order: 0
            visible: root.controlCenterOpen
            Layout.fillWidth: true
            Layout.fillHeight: true
            ControlCenter {
                id: controlCenter
                anchors.fill: parent
                visible: root.controlCenterOpen
                satelliteController: root
                // Same path Escape takes (contentFocus.Keys.onEscapePressed
                // in island/Island.qml): close a satellite/subview first if
                // one is open, otherwise dismiss the island back to rest.
                onBackRequested: {
                    if (!controlCenter.closeExpandedSection())
                        root.dismissRequested(true)
                }
            }
        }

        Reveal {
            token: root.revealToken
            exiting: root.revealExiting
            order: 0
            visible: root.launcherOpen
            Layout.fillWidth: true
            Layout.fillHeight: true
            ApplicationLauncher {
                anchors.fill: parent
                visible: root.launcherOpen
                onDismissRequested: root.dismissRequested(false)
                onPageRequested: page => root.pageSelected(page)
            }
        }

        Reveal {
            token: root.revealToken
            exiting: root.revealExiting
            order: 0
            visible: root.commandLauncherOpen
            Layout.fillWidth: true
            Layout.fillHeight: true
            CommandLauncher {
                anchors.fill: parent
                visible: root.commandLauncherOpen
                onDismissRequested: root.dismissRequested(false)
            }
        }

        Reveal {
            token: root.revealToken
            exiting: root.revealExiting
            order: 0
            visible: root.wallpaperOpen
            Layout.fillWidth: true
            Layout.fillHeight: true
            WallpaperPage {
                anchors.fill: parent
                visible: root.wallpaperOpen
                monitor: root.monitor
            }
        }

        // Insight pages, opened through the `insights` IPC (core/ShellActions.qml
        // insightOpenRequested -> island/Island.qml). The sizes live in
        // island/IslandController.qml's expandedTargetWidth/Height.
        Reveal {
            token: root.revealToken
            exiting: root.revealExiting
            order: 0
            visible: root.calendarOpen
            Layout.fillWidth: true
            Layout.fillHeight: true
            CalendarWeatherPage {
                id: calendarPage
                anchors.fill: parent
                visible: root.calendarOpen
            }
        }

        Reveal {
            token: root.revealToken
            exiting: root.revealExiting
            order: 0
            visible: root.systemOpen
            Layout.fillWidth: true
            Layout.fillHeight: true
            SystemPage {
                anchors.fill: parent
                visible: root.systemOpen
                active: root.systemOpen && root.active
            }
        }

        Reveal {
            token: root.revealToken
            exiting: root.revealExiting
            order: 0
            visible: root.batteryOpen
            Layout.fillWidth: true
            Layout.fillHeight: true
            BatteryPage {
                anchors.fill: parent
                visible: root.batteryOpen
                active: root.batteryOpen && root.active
            }
        }

        Reveal {
            token: root.revealToken
            exiting: root.revealExiting
            order: 0
            visible: root.polkitOpen
            Layout.fillWidth: true
            Layout.fillHeight: true
            PolkitPage {
                id: polkitPage
                anchors.fill: parent
                visible: root.polkitOpen
            }
        }
    }

}
