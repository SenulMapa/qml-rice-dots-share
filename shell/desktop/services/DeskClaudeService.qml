// Desktop adapter for the "claude" module -- DISABLED BY DEFAULT.
//
// impasto's services/ClaudeService.qml runs scripts/claude_usage.py, which
// calls https://api.anthropic.com/v1/messages with the user's own API
// credentials to read back rate-limit headers (session/weekly usage). Per
// this port's brief ("the Claude module stays disabled by default if it
// needs credentials or network calls to Anthropic"), that script was
// deliberately NOT ported and no Process is ever spawned here -- this
// singleton is a static, always-"no usage found" stand-in so
// faces/analogue/ClaudeFace.qml and the modern faces' claude row render
// impasto's own designed empty state instead of a broken binding.
//
// To wire this up for real: port scripts/claude_usage.py to
// scripts/desktop/claude_usage.py, add a DeskSettings.claudeEnabled toggle
// (default false), and replace this file with the real service gated on
// that toggle.

pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property bool available: false
    readonly property bool sessionMeasured: false
    readonly property bool weeklyMeasured: false
    readonly property bool measured: false

    readonly property int blockTokens: 0
    readonly property int blockMessages: 0
    readonly property int weekTokens: 0
    readonly property int weekMessages: 0
    readonly property int peakBlockTokens: 0
    readonly property int peakWeekTokens: 0

    readonly property real sessionFraction: 0
    readonly property real weeklyFraction: 0
    readonly property real gauge: 0
    readonly property color tint: "#8e8e93"
    readonly property string resetsIn: ""

    function messages(count: int): string {
        return `${count}`
    }

    function compact(tokens: int): string {
        if (tokens >= 1000000)
            return `${(tokens / 1000000).toFixed(1)}M`
        if (tokens >= 1000)
            return `${(tokens / 1000).toFixed(1)}k`
        return `${tokens}`
    }

    function percent(fraction: real): string {
        return `${Math.round(fraction * 100)}%`
    }
}
