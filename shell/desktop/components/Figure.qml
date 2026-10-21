// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   F I G U R E                                                            │
// │   a value with its caption                                               │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick
import QtQuick.Layouts
import "../services" as DeskServices

// One reading in three lines: a small-caps label, the number, and a note.
// The number is monospaced so digits do not shift as it changes.
ColumnLayout {
    id: root

    property string label: ""
    property string value: ""
    property string note: ""
    property color valueColor: DeskServices.DeskTheme.text

    spacing: 1

    Text {
        text: root.label
        font.family: DeskServices.DeskTheme.fontFamily
        font.pixelSize: DeskServices.DeskTheme.fontSizeLabel
        font.weight: Font.DemiBold
        font.letterSpacing: 0.6
        color: DeskServices.DeskTheme.textMuted
    }

    Text {
        Layout.fillWidth: true
        text: root.value
        elide: Text.ElideRight
        font.family: DeskServices.DeskTheme.fontMono
        font.pixelSize: DeskServices.DeskTheme.fontSizeLarge
        font.weight: Font.DemiBold
        color: root.valueColor
    }

    Text {
        Layout.fillWidth: true
        visible: root.note !== ""
        text: root.note
        elide: Text.ElideRight
        font.family: DeskServices.DeskTheme.fontFamily
        font.pixelSize: DeskServices.DeskTheme.fontSizeLabel
        color: DeskServices.DeskTheme.textMuted
    }
}
