// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   G   I   T   H   U   B       F   A   C   E                              │
// │   the contribution wall as an object · analogue                          │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick

import "../../services" as DeskServices
import "../../components"

// TODO: components not yet ported

// The contribution wall, with embossed tiles instead of flat ones, and no
// caption or frame. As in the Modern face the cell size is fixed and the width
// decides how many weeks fit; the green and grey are fixed too, and the bevels
// derive from each cell's colour, so `ink` is unused.
Item {
    id: root

    property var ink: DeskServices.DeskDesktopService.inkFor(null)
    property string family: "2x2"

    ContributionGrid {
        anchors.fill: parent
        anchors.margins: 12
        visible: DeskServices.DeskGithubService.available

        weeks: DeskServices.DeskGithubService.weeks
        spacing: 3
        radius: 2.5
        maxCell: 24
        raised: true
    }

    // Says why the wall is empty, as the Modern face does.
    Text {
        anchors.centerIn: parent
        width: parent.width - 24
        visible: !DeskServices.DeskGithubService.available
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: DeskServices.DeskSettings.githubUser.trim() === "" ? "No GitHub user set" : "GitHub is out of reach"
        font.family: DeskServices.DeskTheme.fontFamily
        font.pixelSize: DeskServices.DeskTheme.fontSizeSmall
        color: root.ink.muted
    }
}
