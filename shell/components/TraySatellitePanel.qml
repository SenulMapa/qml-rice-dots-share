import QtQuick
import QtQuick.Layouts
import Quickshell
import "../core"
import "../services"

// Minimal tray-menu satellite content, hosted in the right satellite next to
// the island (see island/Island.qml). Styled like ControlDetailPanel: serif
// header + round back-arrow button, flat text rows, no card backgrounds,
// separators as spacing not lines. Uses Quickshell's own QsMenuOpener/
// QsMenuEntry API (the same one end4-pC's SysTrayMenu*.qml reads) rather
// than any of end4-pC's own widget code.
Item {
    id: root

    required property var item

    property var stack: item ? [item.menu] : []
    onItemChanged: stack = item ? [item.menu] : []
    readonly property bool atRoot: stack.length <= 1

    readonly property int contentHeight: Math.round(col.implicitHeight + Theme.u(0.51) * 2)

    QsMenuOpener {
        id: opener
        menu: root.stack.length > 0 ? root.stack[root.stack.length - 1] : null
    }

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.leftMargin: Theme.u(0.44)
        anchors.rightMargin: Theme.u(0.44)
        anchors.topMargin: Theme.u(0.51)
        anchors.bottomMargin: Theme.u(0.51)
        spacing: Theme.u(0.2)

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.u(0.2)

            Rectangle {
                visible: !root.atRoot
                Layout.preferredWidth: Theme.u(0.5)
                Layout.preferredHeight: Theme.u(0.5)
                radius: width / 2
                color: Theme.surfaceContainer

                BackArrowIcon {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: -1
                    color: AdaptiveColor.glassTextDim
                    size: Theme.u(0.24)
                }
                TapHandler { onTapped: root.stack = root.stack.slice(0, -1) }
            }

            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.item ? (root.item.title || root.item.id || "") : ""
                color: AdaptiveColor.glassText
                font.family: Config.appearance.displayFontFamily
                font.pixelSize: Theme.u(0.5)
            }
        }

        Flickable {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(rows.implicitHeight, Theme.u(9.5))
            contentWidth: width
            contentHeight: rows.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: rows
                width: parent.width
                spacing: Theme.u(0.18)

                Repeater {
                    model: opener.children
                    delegate: Item {
                        required property QsMenuEntry modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: modelData.isSeparator ? Theme.u(0.2) : Theme.u(0.56)

                        RowLayout {
                            anchors.fill: parent
                            visible: !modelData.isSeparator
                            opacity: modelData.enabled ? 1 : 0.42
                            spacing: Theme.u(0.2)

                            Text {
                                visible: modelData.buttonType !== QsMenuButtonType.None
                                text: modelData.checkState === Qt.Checked ? "✓" : ""
                                color: AdaptiveColor.activeFill
                                font.pixelSize: Theme.u(0.26)
                            }
                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: modelData.text
                                color: AdaptiveColor.glassText
                                font.family: Config.appearance.fontFamily
                                font.pixelSize: Theme.u(0.3)
                            }
                            Text {
                                visible: modelData.hasChildren
                                text: "›"
                                color: AdaptiveColor.glassTextDim
                            }
                        }
                        // Never triggered live: activating a real entry
                        // changes real application state (see HANDOVER).
                        TapHandler {
                            enabled: !modelData.isSeparator && modelData.enabled
                            onTapped: modelData.hasChildren
                                ? root.stack = root.stack.concat([modelData])
                                : modelData.triggered()
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: opener.children.values.length === 0
                    text: "No items"
                    color: AdaptiveColor.glassTextDim
                    font.family: Config.appearance.fontFamily
                    font.pixelSize: Theme.u(0.28)
                }
            }
        }
    }
}
