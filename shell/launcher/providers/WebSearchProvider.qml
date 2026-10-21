pragma Singleton
import QtQuick
import Quickshell
import "search.js" as Search

// One row, always last: hands the typed text to the default browser.
// CommandPaletteService keeps it at the bottom whatever the other groups hold.
QtObject {
    readonly property string providerId: "web"
    readonly property string displayName: "Web"

    function query(queryText: string, limit: int): var {
        const text = queryText.trim()
        if (text.length === 0 || limit < 1)
            return []
        return [{
            key: "web-search:" + text,
            provider: providerId,
            group: displayName,
            kind: "web-search",
            actionId: "web-search",
            title: `Search the web for "${text}"`,
            subtitle: "DuckDuckGo in your default browser",
            icon: "󰖟",
            iconKind: "glyph",
            badge: "Web",
            score: 0,
            pinBottom: true,
            query: text,
            enabled: true
        }]
    }

    function execute(result): var {
        if (!result?.query)
            return { handled: false }
        Quickshell.execDetached(["xdg-open", Search.webSearchUrl(result.query)])
        return { handled: true, dismiss: true }
    }
}
