import QtQuick
import QtQuick.Layouts
import "../components"
import "../core"
import "../services"

RowLayout {
    id: root

    signal pageRequested(string page)
    spacing: Theme.space2
    // Each of the three cards below is its own reveal step (orders 0-2) --
    // see panels/Dashboard.qml, which passes these straight through.
    property int revealToken: 0
    property bool revealExiting: false

    readonly property var latestNotification: NotificationService.history.length > 0
        ? NotificationService.history[0] : null

    function timeAgo(timestamp): string {
        if (!timestamp)
            return ""
        const minutes = Math.max(0, Math.floor((Date.now() - timestamp) / 60000))
        if (minutes < 1)
            return "Now"
        if (minutes < 60)
            return minutes + "m"
        const hours = Math.floor(minutes / 60)
        return hours < 24 ? hours + "h" : Math.floor(hours / 24) + "d"
    }

    Reveal {
        token: root.revealToken
        exiting: root.revealExiting
        order: 0
        Layout.preferredWidth: 196
        Layout.fillHeight: true

    DashboardCard {
        anchors.fill: parent
        accent: AdaptiveColor.activeFill
        onActivated: root.pageRequested("calendar")

        // Figma (node 7:4, "Calendar cell") gave a clock face, not a date
        // face -- a large thin/light serif HOUR numeral, a small mono
        // MINUTES readout sitting on the numeral's top line, the uppercase
        // mono weekday directly under it, then the month and "Calendar ›"
        // link. Figma's literal px values (30/14/10/8/10) were copied into
        // this cell 1:1, but measured against the live dashboard (789px
        // wide, matching the Figma "Overview dashboard" frame exactly) the
        // cell itself was built narrower than Figma's own 216px calendar
        // cell (174px here vs 216px there) -- so those sizes were already
        // cropped tight before the owner's own "make it bigger" ask. Sized
        // up here for a dominant hour numeral (the ask), a legible month
        // line (8px was unreadable on a real screen, not just small), and
        // a slightly widened cell (196px) so the bigger glyphs get breathing
        // room without the neighbouring weather cell losing much space.
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.space3
            spacing: 0

            RowLayout {
                Layout.alignment: Qt.AlignLeft | Qt.AlignTop
                spacing: 3

                Text {
                    Layout.alignment: Qt.AlignTop
                    text: Qt.formatDateTime(ShellState.now,
                        Config.appearance.use24HourClock ? "HH" : "h")
                    color: AdaptiveColor.glassText
                    font.family: Config.appearance.displayFontFamily
                    font.pixelSize: 42
                }

                ColumnLayout {
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: 7
                    spacing: 1
                    Text {
                        // Geist Mono is monospaced/tabular by construction --
                        // minutes never shift width as they tick over.
                        text: ":" + Qt.formatDateTime(ShellState.now, "mm")
                        color: AdaptiveColor.glassText
                        font.family: Config.appearance.monoFontFamily
                        font.pixelSize: 17
                        font.weight: Font.Medium
                    }
                    Text {
                        text: Qt.formatDate(ShellState.now, "dddd").toUpperCase()
                        color: AdaptiveColor.activeFill
                        font.family: Config.appearance.monoFontFamily
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        font.letterSpacing: 1
                    }
                }
            }

            Text {
                Layout.topMargin: 2
                text: Qt.formatDate(ShellState.now, "MMMM yyyy")
                color: AdaptiveColor.glassTextDim
                font.family: Config.appearance.fontFamily
                font.pixelSize: Theme.dashCaption
            }

            Text {
                Layout.topMargin: 3
                text: "Calendar ›"
                color: AdaptiveColor.glassTextDim
                font.family: Config.appearance.fontFamily
                font.pixelSize: Theme.dashCaption
            }

            Item { Layout.fillHeight: true }
        }
    }
    }

    Reveal {
        token: root.revealToken
        exiting: root.revealExiting
        order: 1
        Layout.fillWidth: true
        Layout.fillHeight: true

    DashboardCard {
        id: weatherCard
        anchors.fill: parent
        accent: Theme.tertiary
        onActivated: root.pageRequested("weather")

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.space3
            spacing: Theme.space1

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Theme.space3
                Text {
                    text: WeatherService.available ? WeatherService.icon : "󰖐"
                    color: Theme.tertiary
                    font.family: Config.appearance.monoFontFamily
                    font.pixelSize: 40
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        text: WeatherService.available
                            ? WeatherService.temperatureLabel : "—"
                        color: AdaptiveColor.glassText
                        font.family: Config.appearance.monoFontFamily
                        font.pixelSize: 28
                        font.weight: Font.DemiBold
                    }
                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: -2
                        text: WeatherService.statusLabel
                        color: AdaptiveColor.glassTextDim
                        elide: Text.ElideRight
                        font.family: Config.appearance.fontFamily
                        font.pixelSize: Theme.dashCaption
                    }
                }
                ColumnLayout {
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    spacing: 0
                    Text {
                        Layout.alignment: Qt.AlignRight
                        text: Config.weather.locationName
                        color: AdaptiveColor.glassText
                        font.family: Config.appearance.fontFamily
                        font.pixelSize: Theme.dashBody
                        font.weight: Font.DemiBold
                        style: Theme.dashHeavy
                        styleColor: AdaptiveColor.glassText
                    }
                    Text {
                        Layout.alignment: Qt.AlignRight
                        text: WeatherService.highLowLabel
                        color: AdaptiveColor.glassTextDim
                        font.family: Config.appearance.monoFontFamily
                        font.pixelSize: 9
                    }
                    Text {
                        Layout.alignment: Qt.AlignRight
                        text: "Rise " + WeatherService.sunrise + "  ·  Set "
                            + WeatherService.sunset
                        color: AdaptiveColor.glassTextDim
                        font.family: Config.appearance.monoFontFamily
                        font.pixelSize: 9
                    }
                }
            }

        }
    }
    }

    Reveal {
        token: root.revealToken
        exiting: root.revealExiting
        order: 2
        Layout.preferredWidth: 184
        Layout.fillHeight: true

    DashboardCard {
        anchors.fill: parent
        accent: AdaptiveColor.activeFill
        onActivated: root.pageRequested("notifications")

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.space3
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: NotificationService.doNotDisturb ? "󰂛" : "󰂚"
                    color: AdaptiveColor.activeFill
                    font.family: Config.appearance.monoFontFamily
                    font.pixelSize: 14
                }
                Text {
                    Layout.fillWidth: true
                    text: "NOTIFICATIONS"
                    color: AdaptiveColor.glassTextDim
                    font.family: Config.appearance.monoFontFamily
                    font.pixelSize: 9
                    font.letterSpacing: 1
                }
                Text {
                    visible: NotificationService.count > 0
                    text: NotificationService.count.toString()
                    color: AdaptiveColor.activeFill
                    font.family: Config.appearance.monoFontFamily
                    font.pixelSize: 9
                    font.weight: Font.Bold
                }
            }
            Item { Layout.fillHeight: true }
            Text {
                Layout.fillWidth: true
                text: root.latestNotification?.title || "You're all caught up"
                color: AdaptiveColor.glassText
                elide: Text.ElideRight
                font.family: Config.appearance.fontFamily
                font.pixelSize: Theme.dashLabel
                font.weight: Font.DemiBold
                style: Theme.dashHeavy
                styleColor: AdaptiveColor.glassText
            }
            Text {
                Layout.fillWidth: true
                text: root.latestNotification
                    ? root.latestNotification.appName + " · "
                        + root.timeAgo(root.latestNotification.timestamp)
                    : "No recent notifications"
                color: AdaptiveColor.glassTextDim
                elide: Text.ElideRight
                font.family: Config.appearance.fontFamily
                font.pixelSize: Theme.dashCaption
            }
        }
    }
    }

    component WeatherDatum: Item {
        id: datum
        property string icon: ""
        property string value: ""
        implicitHeight: 14

        RowLayout {
            anchors.centerIn: parent
            spacing: Theme.space1
            Text {
                text: datum.icon
                color: AdaptiveColor.activeFill
                font.family: Config.appearance.monoFontFamily
                font.pixelSize: 10
            }
            Text {
                text: datum.value
                color: AdaptiveColor.glassTextDim
                font.family: Config.appearance.monoFontFamily
                font.pixelSize: 9
                font.weight: Font.DemiBold
            }
        }
    }
}
