import QtQuick
import "../core"

/**
 * MacStyleRoot -- the root of the Tahoe ("mac") presentation (spec section 2).
 *
 * shell.qml loads this with `Loader { active: Config.appearance.macStyle }`,
 * so it exists only while uiStyle is "mac". Every stub below is alive exactly
 * then. The pill presentation is untouched and stays loaded in both styles.
 *
 * Routing, all from the pill side (see island/IslandController.qml):
 *   - notification toast  -> MacBanners        (direct: NotificationService.presentationRequested)
 *   - notifications page  -> MacNotificationCenter.request(action)  (via macSurfaceRequested)
 *   - launcher page       -> MacSpotlight.request(action)          (via macSurfaceRequested)
 *   - ringing call        -> MacCallBanner     (direct: PhoneService.call)
 *   - Quick Look (Space)  -> MacQuickLook      (via ShellActions.quickLookRequested)
 *   - control centre      -> MacControlCenter.request(action)  (via macSurfaceRequested, "overview" page)
 * Live activities (music, timer, active call, recording) stay in the pill.
 */
QtObject {
    id: root

    readonly property MacBanners banners: MacBanners { }
    readonly property MacNotificationCenter notificationCenter: MacNotificationCenter { }
    readonly property MacControlCenter controlCenter: MacControlCenter { }
    readonly property MacSpotlight spotlight: MacSpotlight { }
    readonly property MacCallBanner callBanner: MacCallBanner { }
    readonly property MacQuickLook quickLook: MacQuickLook { }

    // Screenshot thumbnail (bottom right). Layer window, so built only with layer
    // shell; it watches the queue file that tools/mac-screenshot/shot writes.
    readonly property Loader shotLoader: Loader {
        active: MacTokens.layerShell
        source: "MacShotWindow.qml"
    }

    // Top-right hot corners that toggle the NC. Layer windows, so built only
    // with layer shell; the offscreen harness never compiles them.
    readonly property Loader cornerLoader: Loader {
        active: MacTokens.layerShell
        source: "MacNcCorner.qml"
        onLoaded: item.center = root.notificationCenter
    }

    // Surface requests from IslandController.macRoute(). Only the pages
    // the pill would otherwise open are forwarded.
    property Connections surfaceLink: Connections {
        target: ShellActions
        function onMacSurfaceRequested(surface: string, action: string): void {
            if (surface === "notifications")
                root.notificationCenter.request(action)
            else if (surface === "launcher")
                root.spotlight.request(action)
            else if (surface === "controlCenter")
                root.controlCenter.request(action)
        }

        // Quick Look: `qml-rice ipc quicklook ...` (tools/quicklook/quicklook).
        function onQuickLookRequested(action: string, path: string): void {
            root.quickLook.request(action, path)
        }
    }
}
