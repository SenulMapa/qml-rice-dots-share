import QtQuick
import "../core"

/**
 * Pill — the island's painted surface.
 *
 * Width, height and radius are driven by MotionValues, and NOTHING inside the
 * pill binds to its width or height. That is the load-bearing rule: Qt's docs
 * warn that binding-based positioning "incurs a performance cost", and the cost
 * is the dependency cascade, not the arithmetic. A geometry change that
 * reaches a layout re-runs the layout every frame of the morph; a geometry
 * change that only paints does not. Children position against Theme constants
 * and their own implicit sizes instead.
 *
 * Surface treatment is four devices, all free on integrated graphics because
 * none of them is translucency:
 *   gradient   a vertex colour on the Rectangle
 *   hairline   border.width: 1
 *   sheen      a 1px Rectangle inset from the corners by 0.6 * radius, so the
 *              rounded corner never clips it mid-curve
 *   shadow     the only thing that costs anything; see quality tiers
 */
Item {
    id: root

    property real targetW: Theme.pillW
    property real targetH: Theme.pillH

    readonly property alias contentWidth: body.width
    readonly property alias contentHeight: body.height
    default property alias content: holder.data

    implicitWidth: body.width
    implicitHeight: body.height

    MotionValue { id: mvW; unit: "px"; target: root.targetW; value: root.targetW }
    MotionValue { id: mvH; unit: "px"; target: root.targetH; value: root.targetH }

    Rectangle {
        id: body
        anchors.horizontalCenter: parent.horizontalCenter
        width: mvW.value
        height: mvH.value
        radius: Theme.radiusFor(height)
        border.width: 1
        border.color: Theme.hairline
        antialiasing: true

        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.surface_top }
            GradientStop { position: 1.0; color: Theme.surface_bot }
        }

        // Sheen: reads as light landing on the top edge. Inset by 0.6 * radius
        // so it stops where the corner curve begins rather than being sliced
        // by it — the same anchoring Ricelin uses, arrived at independently
        // because a full-bleed highlight looks like a seam.
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 1
            anchors.leftMargin: parent.radius * 0.6
            anchors.rightMargin: parent.radius * 0.6
            height: 1
            color: Theme.sheen
        }

        Item {
            id: holder
            anchors.fill: parent
        }
    }
}
