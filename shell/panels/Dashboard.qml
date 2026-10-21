import QtQuick
import QtQuick.Layouts
import "../components"
import "../core"

Item {
    id: root

    signal pageRequested(string page)
    signal satelliteRequested(string section)
    readonly property bool centerVisible: Config.dashboard.showMedia
        || Config.dashboard.showSystem
    // Passed straight through from island/IslandExpanded.qml. Dashboard is
    // the one page with the FULL per-element treatment (expanded/expanded
    // in the brief's words) rather than a single whole-page Reveal, so it
    // needs the raw token/exiting flag, not a wrapper -- each zone below
    // owns its own Reveal and stagger position.
    property int revealToken: 0
    property bool revealExiting: false

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.space2

        // Hero row cells (calendar, weather, notifications) each stagger
        // individually -- see panels/DashboardHeroRow.qml, which owns
        // orders 0-2 internally.
        DashboardHeroRow {
            visible: Config.dashboard.showHero
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? 104 : 0
            Layout.minimumHeight: visible ? 104 : 0
            Layout.maximumHeight: visible ? 104 : 0
            revealToken: root.revealToken
            revealExiting: root.revealExiting
            onPageRequested: page => root.pageRequested(page)
        }

        RowLayout {
            visible: root.centerVisible
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.space2

            Reveal {
                token: root.revealToken
                exiting: root.revealExiting
                order: 3
                visible: Config.dashboard.showMedia
                Layout.fillWidth: true
                Layout.fillHeight: true
                DashboardMediaCard {
                    anchors.fill: parent
                    visible: Config.dashboard.showMedia
                    onPageRequested: root.pageRequested("media-center")
                }
            }

            // Deliberately narrower than the media card -- the dashboard
            // gets ONE clear focal point (Now Playing, with the cava ring),
            // not two co-equal boxes.
            Reveal {
                token: root.revealToken
                exiting: root.revealExiting
                order: 4
                visible: Config.dashboard.showSystem
                Layout.fillWidth: !Config.dashboard.showMedia
                Layout.preferredWidth: 196
                Layout.fillHeight: true
                DashboardSystemCard {
                    anchors.fill: parent
                    visible: Config.dashboard.showSystem
                    onPageRequested: root.pageRequested("system")
                }
            }
        }

        // Each quick-strip item is its own step -- see
        // panels/DashboardQuickStrip.qml, which owns orders 5+ internally.
        DashboardQuickStrip {
            visible: Config.dashboard.showQuickStrip
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? 48 : 0
            Layout.minimumHeight: visible ? 48 : 0
            Layout.maximumHeight: visible ? 48 : 0
            revealToken: root.revealToken
            revealExiting: root.revealExiting
            onPageRequested: page => root.pageRequested(page)
            onSatelliteRequested: section => root.satelliteRequested(section)
        }
    }
}
