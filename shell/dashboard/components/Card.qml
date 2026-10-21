// Ported from impasto's components/Card.qml
// (github.com/andreumassanet/impasto, GPL-3.0, Andreu Massanet).
//
// The rounded surface every control centre section uses. `bare` drops the
// surface and keeps the contents, for module details shown directly in the
// dashboard.
//
// Adaptation: Theme -> DeskTheme.

import QtQuick
import "../../desktop/services" as Desk
import "../../components"

Squircle {
    id: root

    default property alias content: inner.data
    property int padding: 14
    property bool bare: false

    radius: Desk.DeskTheme.radiusMedium
    color: root.bare ? "transparent" : Desk.DeskTheme.islandSurface
    borderColor: Desk.DeskTheme.islandBorder
    borderWidth: root.bare ? 0 : 1

    Behavior on color { ColorAnimation { duration: Desk.DeskTheme.paletteTransition } }

    Item {
        id: inner
        anchors.fill: parent
        anchors.margins: root.padding
    }
}
