import QtQuick
import QtQuick.Layouts
import "../core"
import "../components"

/**
 * MacWidgetList -- the list widget used for Today (tasks due today) and
 * Reminders (to-do). Spec 3.3: 343 wide, light frosted fill. A title row with
 * the count, then up to three rows with an empty radio ring. The column hides
 * the widget when the list is empty, so this only draws the non-empty state.
 */
Item {
    id: root

    property string label: ""
    property string glyph: ""
    property int count: 0
    property var rows: []

    width: MacTokens.s(MacTokens.ncColumnWidth)
    height: MacTokens.s(MacTokens.ncListWidgetHeight)

    readonly property real pad: MacTokens.s(MacTokens.bannerPad)
    readonly property real rowGap: MacTokens.s(MacTokens.ncListRowPitch) - MacTokens.s(MacTokens.ncListRadio) * 0.64

    TahoeSurface {
        anchors.fill: parent
        kind: "nc"
        radius: MacTokens.s(MacTokens.ncWidgetRadius)
        tintAlpha: MacTokens.frostTintAlpha
        fill: MacTokens.ncWidgetFrost
    }

    // A title row, then one row per item, a radio ring and the text, both
    // left-aligned, on one padding grid.
    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: root.pad
        anchors.rightMargin: root.pad
        anchors.topMargin: root.pad
        anchors.bottomMargin: root.pad
        spacing: root.rowGap

        RowLayout {
            Layout.fillWidth: true
            spacing: root.pad / 2

            Rectangle {
                Layout.preferredWidth: MacTokens.s(MacTokens.ncHourlyIconSize) + MacTokens.s(4)
                Layout.preferredHeight: Layout.preferredWidth
                radius: width / 2
                color: MacTokens.accentBlue
                Text {
                    anchors.centerIn: parent
                    text: root.glyph
                    color: MacTokens.accentOn
                    font.family: MacTokens.displayFamily
                    font.pixelSize: MacTokens.s(MacTokens.ncHourlyTimeSize)
                }
            }
            Text {
                Layout.fillWidth: true
                text: root.label
                color: MacTokens.labelPrimary
                elide: Text.ElideRight
                font.family: MacTokens.textFamily
                font.pixelSize: MacTokens.s(MacTokens.ncWidgetTitleSize)
                font.weight: Font.DemiBold
            }
            Text {
                text: root.count
                color: MacTokens.labelSecondary
                font.family: MacTokens.textFamily
                font.pixelSize: MacTokens.s(MacTokens.ncWidgetTitleSize)
                font.weight: Font.Medium
            }
        }

        Repeater {
            model: root.rows.slice(0, 3)
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: root.pad / 2

                Rectangle {
                    Layout.preferredWidth: MacTokens.s(MacTokens.ncListRadio) * 0.64
                    Layout.preferredHeight: Layout.preferredWidth
                    radius: width / 2
                    color: "transparent"
                    border.width: 1
                    border.color: MacTokens.labelSecondary
                }
                Text {
                    Layout.fillWidth: true
                    text: modelData.text
                    color: MacTokens.labelPrimary
                    horizontalAlignment: Text.AlignLeft
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    font.family: MacTokens.textFamily
                    font.pixelSize: MacTokens.s(MacTokens.ncListRowSize)
                    font.weight: Font.Medium
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
