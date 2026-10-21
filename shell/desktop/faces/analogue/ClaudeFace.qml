// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   C   L   A   U   D   E       F   A   C   E                              │
// │   claude code usage as a fuel gauge                                      │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick
import Quickshell

import "../../services" as DeskServices
import "../../components"

// TODO: components not yet ported

// Claude usage as a fuel gauge: F with the block untouched, E when it is spent,
// red at the empty end. Uses the account's figure when available, else the
// block's elapsed time.
Instrument {
    id: face

    readonly property string figure: !DeskServices.DeskClaudeService.available ? "—"
        : DeskServices.DeskClaudeService.sessionMeasured
        ? DeskServices.DeskClaudeService.percent(DeskServices.DeskClaudeService.sessionFraction)
        : DeskServices.DeskClaudeService.compact(DeskServices.DeskClaudeService.blockTokens)

    line: !DeskServices.DeskClaudeService.available ? "No usage found"
        : (DeskServices.DeskClaudeService.sessionMeasured ? `${face.figure} of this block` : `${face.figure} this block`)
    reading: face.figure
    note: !DeskServices.DeskClaudeService.available ? "no usage found"
        : DeskServices.DeskClaudeService.sessionMeasured
        ? `of this block · resets in ${DeskServices.DeskClaudeService.resetsIn}`
        : `this block · resets in ${DeskServices.DeskClaudeService.resetsIn}`
    filled: true

    Gauge {
        anchors.centerIn: parent
        ink: face.ink
        size: Math.min(parent.width, parent.height)
        fraction: 1 - DeskServices.DeskClaudeService.gauge
        lowIsBad: true
        ends: ["E", "F"]

        ClaudeMark {
            x: (parent.width - width) / 2
            y: parent.height * 0.28
            width: 22
            height: 22
            color: face.ink.text
        }
    }

    extra: [
        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 4

            UsageBar {
                width: parent.width
                progress: DeskServices.DeskClaudeService.weeklyFraction
                fillColor: face.ink.accent
                trackColor: face.ink.raised
            }

            Text {
                text: DeskServices.DeskClaudeService.weeklyMeasured
                    ? `${DeskServices.DeskClaudeService.percent(DeskServices.DeskClaudeService.weeklyFraction)} of the week` : "this week"
                font.family: DeskServices.DeskTheme.fontFamily
                font.pixelSize: DeskServices.DeskTheme.fontSizeLabel
                color: face.ink.muted
            }
        }
    ]
}
