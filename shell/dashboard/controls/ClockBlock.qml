// Ported from impasto's bar/island/controls/ClockBlock.qml
// (github.com/andreumassanet/impasto, GPL-3.0, Andreu Massanet).
//
// The clock. Square: time over the day. Wide: larger time over the full
// date. Uses the configured format, with seconds appended as on the bar.
//
// Adaptation: Theme -> DeskTheme; SettingsService.clockFormat/
// clockShowsSeconds -> DeskSettings' own (identical) properties, already
// shipped by the desktop port for the same purpose.

import QtQuick
import Quickshell
import "../../desktop/services" as Desk
import "../components" as DashComponents

DashComponents.Card {
    id: root

    property int cols: 1
    property int rows: 2

    readonly property bool tall: root.rows >= 4
    readonly property bool wide: root.cols >= 2 && !root.tall

    SystemClock {
        id: clock
        precision: Desk.DeskSettings.clockShowsSeconds
            ? SystemClock.Seconds : SystemClock.Minutes
    }

    readonly property string format: Desk.DeskSettings.clockShowsSeconds
        ? Desk.DeskSettings.clockFormat.replace("mm", "mm:ss")
        : Desk.DeskSettings.clockFormat

    readonly property int timeSize: root.tall ? 64 : (root.wide ? 44 : 30)

    Column {
        anchors.centerIn: parent
        width: parent.width
        spacing: root.tall ? 6 : 2

        Text {
            width: parent.width
            text: Qt.formatDateTime(clock.date, root.format)
            horizontalAlignment: Text.AlignHCenter
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: Desk.DeskTheme.fontSizeLarge
            font.family: Desk.DeskTheme.fontFamily
            font.pixelSize: root.timeSize
            font.weight: Font.DemiBold
            color: Desk.DeskTheme.text
        }

        Text {
            width: parent.width
            text: Qt.formatDateTime(clock.date, root.wide || root.tall ? "dddd d MMMM" : "ddd d MMM")
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            font.family: Desk.DeskTheme.fontFamily
            font.pixelSize: root.tall ? Desk.DeskTheme.fontSizeMedium : Desk.DeskTheme.fontSizeSmall
            color: Desk.DeskTheme.textMuted
        }
    }
}
