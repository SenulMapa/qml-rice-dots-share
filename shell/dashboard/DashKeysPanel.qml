// Simplified port of impasto's bar/island/KeysPanel.qml
// (github.com/andreumassanet/impasto, GPL-3.0, Andreu Massanet).
//
// A read-only keybinding cheat sheet. Upstream builds this from its own
// ShortcutService.sheet, which parses the compositor's bind list into named
// groups -- this shell has no equivalent catalogue service (grepped: no
// ShortcutService, no HyprlandService.loadBinds/sheet). Rather than fabricate
// group labels this shell doesn't know, this panel reads the compositor's
// REAL bind list directly (`hyprctl -j binds`, the same IPC socket every
// other HyprlandService call in this shell already uses) and lists it flat,
// filterable by a text field. Real data, just ungrouped.

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Io
import "../desktop/services" as Desk
import "components" as DashComponents
import "../components"

ColumnLayout {
    id: root

    signal closed()

    spacing: 8

    property var binds: []

    readonly property var filtered: {
        const needle = field.text.toLowerCase()
        if (needle === "")
            return root.binds
        return root.binds.filter(bind =>
            (root.labelOf(bind) + " " + bind.keyLabel).toLowerCase().includes(needle))
    }

    // Hyprland's own `description` where the bind has one -- this config is
    // written in Lua (hl.bind), so EVERY bind's dispatcher reads "__lua" with
    // an opaque callback index as its arg ("__lua 9"), which is what the
    // sheet used to show for all 211 binds. `hyprctl binds -j` carries the
    // real human label alongside it on the 107 that set one; the rest keep
    // the dispatcher/arg fallback.
    function labelOf(bind: var): string {
        return bind.description && bind.description !== ""
            ? bind.description
            : bind.dispatcher + (bind.arg ? (" " + bind.arg) : "")
    }

    function keyLabelOf(bind: var): string {
        const mods = []
        if (bind.modmask & 64) mods.push("Super")
        if (bind.modmask & 1) mods.push("Shift")
        if (bind.modmask & 4) mods.push("Ctrl")
        if (bind.modmask & 8) mods.push("Alt")
        mods.push(bind.key || bind.keycode || "")
        return mods.filter(part => part !== "").join(" + ")
    }

    Process {
        id: query
        command: ["hyprctl", "-j", "binds"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text)
                    root.binds = parsed.map(bind => Object.assign({}, bind, {
                        keyLabel: root.keyLabelOf(bind)
                    }))
                } catch (error) {
                    root.binds = []
                }
            }
        }
    }

    Component.onCompleted: {
        query.running = true
        field.forceActiveFocus()
    }

    TextField {
        id: field
        Layout.fillWidth: true
        placeholderText: "Filter binds…"
        color: Desk.DeskTheme.text
        font.family: Desk.DeskTheme.fontFamily
        background: Squircle {
            radius: Desk.DeskTheme.radiusSmall
            color: Desk.DeskTheme.islandSurfaceHover
            borderColor: Desk.DeskTheme.islandBorder
            borderWidth: 1
        }
    }

    DashComponents.Card {
        Layout.fillWidth: true
        Layout.fillHeight: true
        padding: 6

        ListView {
            id: list
            anchors.fill: parent
            clip: true
            spacing: 2
            model: root.filtered

            delegate: RowLayout {
                required property var modelData
                width: list.width
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: root.labelOf(modelData)
                    elide: Text.ElideRight
                    font.family: Desk.DeskTheme.fontFamily
                    font.pixelSize: Desk.DeskTheme.fontSizeSmall
                    color: Desk.DeskTheme.text
                }

                Squircle {
                    implicitWidth: capText.implicitWidth + 16
                    implicitHeight: 22
                    radius: Desk.DeskTheme.radiusSmall - 2
                    color: Desk.DeskTheme.islandSurface
                    borderColor: Desk.DeskTheme.islandBorder
                    borderWidth: 1

                    Text {
                        id: capText
                        anchors.centerIn: parent
                        text: modelData.keyLabel
                        font.family: Desk.DeskTheme.fontMono
                        font.pixelSize: Desk.DeskTheme.fontSizeLabel
                        color: Desk.DeskTheme.textMuted
                    }
                }
            }
        }
    }
}
