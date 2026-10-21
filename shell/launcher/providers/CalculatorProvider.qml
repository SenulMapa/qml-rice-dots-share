pragma Singleton
import QtQuick
import Quickshell
import "calc.js" as Calc
import "search.js" as Search

QtObject {
    readonly property string providerId: "calculator"
    readonly property string displayName: "Calculator"

    // "=" forces the calculator: that row is the only result, as before.
    // Without it, text that plainly reads as arithmetic ("2+3", "10%3") gets
    // its answer as the pinned top row. Anything else is just a search.
    function query(queryText: string, limit: int): var {
        const text = queryText.trim()
        const typed = text.startsWith("=")
        if (limit < 1 || (!typed && !Search.isArithmetic(text)))
            return []
        const expression = typed ? text.slice(1).trim() : text
        const outcome = Calc.evaluate(expression)
        if (!typed && !outcome.ok)
            return []
        return [{
            key: `calculator:${expression}`,
            provider: providerId,
            group: displayName,
            kind: "calculator",
            actionId: "copy-calculator-answer",
            title: outcome.ok ? outcome.text : "…",
            subtitle: outcome.ok ? expression : "Keep typing an expression",
            answer: outcome.ok ? outcome.text : "",
            icon: "=",
            iconKind: "glyph",
            badge: outcome.ok ? "Copy" : "",
            score: 1000,
            pinTop: !typed,
            enabled: outcome.ok
        }]
    }

    function execute(result): var {
        if (!result?.enabled || !result.answer)
            return { handled: false }
        // "--" so a negative answer such as -8 is not read as a wl-copy flag.
        Quickshell.execDetached(["wl-copy", "--", result.answer])
        return { handled: true, dismiss: true }
    }
}
