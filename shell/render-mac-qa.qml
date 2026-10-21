// Offscreen render harness for the mac (Tahoe) surfaces, for QA of the stack,
// the Notification Center layout and the Spotlight panel.
//
//   QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=rhi QSG_RHI_BACKEND=opengl \
//     XDG_STATE_HOME=/tmp/mqa-state XDG_CACHE_HOME=/tmp/mqa-cache \
//     QMLRICE_NOTIFICATION_SERVER=0 timeout 25 qs -p <abs path>/render-mac-qa.qml
//
// Grabs the three surfaces with fixture data into /tmp/shellqa/mac-*.png and
// quits. Nothing here opens a layer window, grabs input or touches live state.
// The layer-only parts (the "+N" chip under the stack, which lives in
// MacBannerWindow) are not drawn offscreen; the front stack is.
import QtQuick
import Quickshell
import "core"
import "services"
import "mac"

Item {
    id: root
    width: 1480
    height: 1100

    readonly property real now: Date.now()

    function fixture(id, app, title, body, minutesAgo, critical): var {
        return {
            id: id, timestamp: now - minutesAgo * 60000, appName: app, appIcon: "", desktopEntry: "",
            image: "", title: title, body: body, urgency: critical ? 2 : 1, critical: critical,
            actions: [], provenance: null, active: true, source: null
        }
    }

    readonly property var history: [
        fixture(1, "Mail", "Quarterly report ready", "Finance sent the Q3 PDF for review", 1, false),
        fixture(2, "Messages", "Sam", "Are you free for lunch today?", 3, false),
        fixture(3, "Messages", "Sam", "Sent you the photos from Sunday", 4, false),
        fixture(4, "Calendar", "Standup in 10 minutes", "Team room, weekly sync", 6, false),
        fixture(5, "Slack", "#design", "Priya mentioned you in a thread about the nav", 9, false),
        fixture(6, "Slack", "#design", "Can we review the glass tint tomorrow?", 11, false),
        fixture(7, "Firefox", "Download finished", "invoice-2026.pdf saved to Downloads", 14, false),
        fixture(8, "System", "Battery at 20%", "Plug in soon to avoid sleep", 20, false)
    ]

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#7fa3b3" }
            GradientStop { position: 0.55; color: "#d9a57a" }
            GradientStop { position: 1.0; color: "#c96f3a" }
        }
    }

    // Front stack: three banners, 10 pt apart (the pitch the window uses).
    Column {
        id: stack
        x: 480
        y: 40
        spacing: MacTokens.s(MacTokens.bannerStackGap)

        MacBanner { width: MacTokens.s(MacTokens.bannerWidth) + MacTokens.s(MacTokens.bannerInsetRight); entry: root.history[1]; shown: 1; held: false }
        MacBanner { width: MacTokens.s(MacTokens.bannerWidth) + MacTokens.s(MacTokens.bannerInsetRight); entry: root.history[2]; shown: 1; held: false }
        MacBanner { width: MacTokens.s(MacTokens.bannerWidth) + MacTokens.s(MacTokens.bannerInsetRight); entry: root.history[3]; shown: 1; held: false }
        MacBanner { width: MacTokens.s(MacTokens.bannerWidth) + MacTokens.s(MacTokens.bannerInsetRight); entry: ({ id: 99, timestamp: root.now, appName: "firefox", appIcon: "/usr/share/icons/hicolor/48x48/apps/firefox.png", desktopEntry: "", image: "", title: "Icon test", body: "absolute path", urgency: 1, critical: false, actions: [], provenance: null, active: true, source: null }); shown: 1; held: false }
    }

    MacNotificationColumn {
        x: 1480 - MacTokens.s(MacTokens.ncColumnWidth) - 40
        y: 0
        width: MacTokens.s(MacTokens.ncColumnWidth) + 40
        height: 1100
        notifications: root.history
        shown: 1
    }

    // Reminders widget with rows (the live to-do list is empty on this machine).
    MacWidgetList {
        x: 40
        y: 560
        label: "Reminders"
        glyph: "✓"
        count: 3
        rows: [{ text: "Call the dentist" }, { text: "Buy oat milk" }, { text: "Send the invoice to Finance" }]
    }

    // Parked on the left third of the frame; Spotlight is checked on its own.
    MacSpotlightPanel {
        x: 40
        y: 40
        provider: QtObject {
            property int revision: 0
            function search(text, limit): var {
                return [
                    { title: "Discord", subtitle: "All-in-one voice and text chat", kind: "Application", icon: "" },
                    { title: "Steam", subtitle: "Application for managing and playing games", kind: "Application", icon: "" },
                    { title: "Thunar File Manager", subtitle: "Browse the filesystem", kind: "Application", icon: "" },
                    { title: "Slack", subtitle: "Slack Desktop", kind: "Application", icon: "" }
                ]
            }
            function execute(item, a, b): var { return { ok: true, text: "" } }
        }
    }

    Timer {
        interval: 800
        running: true
        onTriggered: {
            root.grabToImage(result => { result.saveToFile("/tmp/shellqa/mac-qa-all.png"); Qt.quit() })
        }
    }
}
