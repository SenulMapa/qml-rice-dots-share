import QtQuick
import QtQuick.Layouts
import Quickshell
import "../components"
import "../core"
import "../services"

Squircle {
    id: root

    required property var result
    property bool selected: false
    signal activated()
    signal pointed()

    // Ink (Config.appearance.ink): 52px rows on black, selection is a flat
    // inkRaised r14 pill, real theme icons at 32px with no tile.
    readonly property bool ink: Config.appearance.ink
    // Ink calculator row: answer in Instrument Serif right-aligned, the
    // expression 13/500 t2 on the left. No icon or badge on this row.
    readonly property bool calcRow: root.ink && root.result.kind === "calculator"

    implicitHeight: root.calcRow ? 84 : root.ink ? 52 : Theme.u(1.1)
    // Rounder, per the owner: a soft capsule instead of a barely-rounded
    // slab. Comfortably clears the Theme.u(0.3) floor.
    radius: root.ink ? Theme.rCtl : Theme.u(0.4)
    // A soft primary-tinted wash, not a saturated accent slab -- text stays
    // AdaptiveColor.glassText on it instead of needing an on-accent colour.
    color: root.ink
        ? (selected ? Theme.inkRaised : "transparent")
        : selected ? Qt.alpha(AdaptiveColor.activeFill, 0.18)
        : resultHover.hovered ? Theme.surfaceContainerHigh : "transparent"
    opacity: result.enabled ? 1 : 0.46

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: root.ink ? 12 : Theme.u(0.28)
        anchors.rightMargin: root.ink ? 12 : Theme.u(0.28)
        spacing: root.ink ? 14 : Theme.u(0.24)

        Item {
            visible: !root.calcRow
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: root.ink ? 32 : Theme.u(0.78)
            Layout.preferredHeight: root.ink ? 32 : Theme.u(0.78)

            // Every icon -- themed or glyph fallback -- sits in the same
            // rounded tile now, so a real app icon doesn't look like a
            // different kind of row from the fallback letter/glyph case.
            Squircle {
                anchors.fill: parent
                visible: !root.ink
                radius: Theme.u(0.22)
                color: Theme.surfaceContainerHigh
            }

            // Ink: commands get a 32px inkRaised circle carrying the glyph.
            Rectangle {
                anchors.fill: parent
                visible: root.ink && root.result.iconKind === "glyph"
                radius: width / 2
                color: root.selected ? Theme.inkRaised2 : Theme.inkRaised
            }

            // Ink commands with a Lucide name draw Icon instead of the glyph.
            Icon {
                anchors.centerIn: parent
                visible: root.ink && !!root.result.lucide
                name: root.result.lucide ?? ""
                size: 16
                color: Theme.t1
            }

            Text {
                anchors.centerIn: parent
                visible: themedIcon.status !== Image.Ready && !(root.ink && !!root.result.lucide)
                text: root.result.iconKind === "glyph" ? root.result.icon : "󰣆"
                color: root.ink ? Theme.t1 : AdaptiveColor.glassTextDim
                font.family: Config.appearance.monoFontFamily
                font.pixelSize: root.ink ? 16 : Theme.u(0.32)
            }

            Image {
                id: themedIcon
                anchors.fill: parent
                anchors.margins: root.ink ? 0 : Theme.u(0.1)
                visible: root.result.iconKind === "theme"
                source: visible && root.result.icon
                    ? Quickshell.iconPath(root.result.icon, true) : ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
            }
        }

        ColumnLayout {
            id: textColumn
            visible: !root.calcRow
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 1
            // Qt.AlignVCenter centres this column's LAYOUT box -- each
            // line's full ascent+descent, including whatever unused
            // descender space the glyphs on THIS particular row don't
            // touch -- not the rendered ink. Measured on the live launcher
            // (grim + PIL): row highlight 90-137, combined title+subtitle
            // ink 100-129 -- 10px above, 8px below, a 2px gap asymmetry.
            // Nudging the ink up 1px (both gaps become 9) closes it to
            // within 1px; render-only, so it doesn't perturb what
            // ColumnLayout measures for spacing.
            transform: Translate { y: -1 }

            Text {
                Layout.fillWidth: true
                text: root.result.title
                color: root.ink ? Theme.t1 : AdaptiveColor.glassText
                elide: Text.ElideRight
                font.family: root.ink ? Theme.fontUi : Config.appearance.fontFamily
                font.pixelSize: root.ink ? 15 : Theme.textBody
                font.weight: root.ink ? Font.DemiBold : Font.Medium
            }

            Text {
                Layout.fillWidth: true
                visible: text.length > 0
                text: root.result.subtitle
                color: root.ink ? Theme.t2 : AdaptiveColor.glassTextDim
                elide: Text.ElideRight
                font.family: root.ink ? Theme.fontUi : Config.appearance.fontFamily
                font.pixelSize: root.ink ? 12 : Theme.textSmall
            }
        }

        RowLayout {
            visible: root.calcRow
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 12

            Text {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: root.result.subtitle
                color: Theme.t2
                elide: Text.ElideRight
                font.family: Theme.fontUi
                font.pixelSize: 13
                font.weight: Font.Medium
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: root.result.title
                color: Theme.t1
                font.family: Theme.fontSerif
                font.pixelSize: 44
                horizontalAlignment: Text.AlignRight
            }
        }

        // A badge may stay only as dim Geist Mono text, no box, no "↵"
        // affordance. Ink: dim Geist 12/500 (showcase "Open" hint).
        Text {
            Layout.alignment: Qt.AlignVCenter
            visible: text.length > 0 && !root.calcRow
            text: root.result.badge
            color: root.ink ? Theme.t3 : Theme.outline
            font.family: root.ink ? Theme.fontUi : Config.appearance.monoFontFamily
            font.pixelSize: root.ink ? 12 : Theme.textSmall
            font.weight: root.ink ? Font.Medium : Font.Normal
        }
    }

    HoverHandler {
        id: resultHover
        enabled: root.result.enabled
        onHoveredChanged: {
            if (hovered)
                root.pointed()
        }
    }
    TapHandler {
        enabled: root.result.enabled && root.result.executable !== false
        onTapped: root.activated()
    }

    Behavior on color {
        ColorAnimation {
            duration: Animations.fast
            easing.type: Animations.emphasizedEase
        }
    }
}
