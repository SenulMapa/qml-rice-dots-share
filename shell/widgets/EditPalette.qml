// DEPRECATED: Old widget system. Use desktop/ instead
import QtQuick
import "../core"
import "../services"
import "../components"

/**
 * EditPalette -- the small add-widget strip shown while WidgetStore.editMode
 * is on. Tapping a chip adds that widget type to this screen at a default
 * spot (WidgetStore.addWidget); the user drags it into place afterwards.
 * Nothing here is instantiated unless edit mode is active (see WidgetHost's
 * Loader.active).
 */
Item {
    id: root

    required property string screenName

    // Wraps rather than growing indefinitely wide -- the registry has
    // grown from 4 to 10 entries (see services/WidgetStore.qml) and a
    // single Row of 10 chips anchored near the screen's left edge would
    // run straight off the right edge of any normal monitor, taking the
    // now-unreachable chips' click targets with it (WidgetLayer's mask is
    // built from this item's own bounds -- see widgets/WidgetLayer.qml --
    // so anything rendered outside them is exactly as dead as the
    // WidgetFrame button-margin bug fixed alongside this).
    readonly property real maxRowWidth: 420
    implicitHeight: flow.implicitHeight + Theme.space3 * 2
    implicitWidth: root.maxRowWidth + Theme.space3 * 2

    Squircle {
        anchors.fill: parent
        radius: Theme.radiusFor(height)
        color: Theme.surfaceContainerHigh
        borderWidth: 1
        borderColor: Theme.outlineVariant
    }

    Flow {
        id: flow
        anchors.centerIn: parent
        width: root.maxRowWidth
        spacing: Theme.space2

        Repeater {
            model: WidgetStore.availableTypes()

            Rectangle {
                id: chip
                required property var modelData
                width: label.implicitWidth + Theme.space3 * 2
                height: label.implicitHeight + Theme.space2 * 2
                radius: height / 2
                color: chipArea.pressed ? Theme.primaryContainer : Theme.surfaceContainer

                Text {
                    id: label
                    anchors.centerIn: parent
                    text: "+ " + chip.modelData.label
                    font.family: Config.appearance.fontFamily
                    font.pixelSize: Theme.textSmall
                    color: Theme.surfaceText
                }

                MouseArea {
                    id: chipArea
                    anchors.fill: parent
                    onClicked: WidgetStore.addWidget(root.screenName,
                        chip.modelData.type)
                }
            }
        }
    }
}
