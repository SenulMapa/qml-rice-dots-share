pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * PreviewService -- lets a screenshot-verification pass render the OSD, the
 * notification popup and an armed session tile with FAKE data, entirely
 * bypassing PipeWire/backlight/D-Bus/SessionService. Exists ONLY when
 * QMLRICE_PREVIEW=1 (`enabled` below): the `preview` IPC target itself only
 * exists behind a LazyLoader gated on that same env var, exactly like
 * services/PolkitPreviewService.qml's `polkit` target -- `qs ipc show`
 * without the variable set will not list it at all.
 *
 * Every consumer (island/IslandController.qml, island/IslandNotification.qml,
 * panels/SessionPage.qml) only ever reads a plain property here or calls a
 * function that sets one -- nothing in this file imports or calls into
 * AudioService, BrightnessService, SessionService or NotificationService.
 */
QtObject {
    id: root

    readonly property bool enabled: Quickshell.env("QMLRICE_PREVIEW") === "1"

    // ---- OSD ----------------------------------------------------------
    property string osdKind: "volume"
    property real osdPercent: 0
    signal osdRequested()

    function requestOsd(kind: string, percent: int): void {
        osdKind = kind
        osdPercent = Math.max(0, Math.min(100, percent)) / 100
        osdRequested()
    }

    // ---- Notification popup --------------------------------------------
    // A fake entry shaped exactly like services/NotificationService.qml's
    // real ones (see receive()) but with `actions: []`/`provenance: null` --
    // this can never invoke a real action or claim real window provenance.
    property bool notificationPreviewing: false
    property var notificationEntry: null
    signal notificationRequested()

    function requestNotification(appName: string, summary: string,
            body: string, critical: bool): void {
        notificationEntry = {
            id: -1,
            appName: appName && appName.length > 0 ? appName : "Preview",
            appIcon: "",
            image: "",
            desktopEntry: "",
            title: summary && summary.length > 0 ? summary : "Notification",
            body: body || "",
            critical: !!critical,
            actions: [],
            provenance: null
        }
        notificationPreviewing = true
        notificationRequested()
    }

    function clearNotification(): void {
        notificationPreviewing = false
    }

    // ---- Session arm ----------------------------------------------------
    // Visual only -- panels/SessionPage.qml calls its ArmState's arm()
    // (never press()), which can never fire/execute an action.
    property string armedAction: ""
    signal sessionArmRequested()

    function requestSessionArm(action: string): void {
        armedAction = action || ""
        sessionArmRequested()
    }

    // ---- Island hover -----------------------------------------------------
    // Forces island/IslandController.qml's visualState to "hover" so the
    // hover pill can be screenshotted without a real pointer -- see its
    // `previewHoverForced` read of this property. Always false (and this
    // whole property inert) unless `enabled`.
    property bool hoverForced: false

    function requestHover(on: bool): void {
        hoverForced = enabled && !!on
    }

    // ---- Media presentation ---------------------------------------------
    // Fires the same "new track" presentation a real MediaService track
    // change takes (island/IslandController.qml's `previewLink` below),
    // using whatever MediaService already has (real MPRIS data, even
    // paused) -- never invents fake metadata.
    signal mediaRequested()

    function requestMedia(): void {
        mediaRequested()
    }

    // ---- Lyric override -----------------------------------------------
    // Overrides the resting pill's displayed lyric line -- see
    // island/IslandRestItem.qml's Connections to this property and
    // island/Island.qml's lyricsVisible binding, both gated on `enabled`.
    // A long string makes the band's own marquee scroll for feather-edge
    // verification; an empty string clears the override.
    property string lyricOverride: ""

    function requestLyric(text: string): void {
        lyricOverride = enabled ? (text || "") : ""
    }

    property LazyLoader ipcLoader: LazyLoader {
        active: root.enabled

        IpcHandler {
            target: "preview"

            function osd(kind: string, percent: int): string {
                root.requestOsd(kind, percent)
                return "PREVIEW_OSD_OK"
            }

            function notification(appName: string, summary: string,
                    body: string, critical: bool): string {
                root.requestNotification(appName, summary, body, critical)
                return "PREVIEW_NOTIFICATION_OK"
            }

            function sessionArm(action: string): string {
                root.requestSessionArm(action)
                return "PREVIEW_SESSION_ARM_OK"
            }

            function hover(on: bool): string {
                root.requestHover(on)
                return "PREVIEW_HOVER_OK"
            }

            function lyric(text: string): string {
                root.requestLyric(text)
                return "PREVIEW_LYRIC_OK"
            }

            function media(): string {
                root.requestMedia()
                return "PREVIEW_MEDIA_OK"
            }
        }
    }
}
