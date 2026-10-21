pragma Singleton
import QtQuick
import "providers"

QtObject {
    // The file search finishes asynchronously; its revision makes the palette
    // re-run the query when filename results arrive.
    readonly property int revision: FileSearchProvider.revision
    readonly property var providers: [
        ApplicationsProvider,
        CalculatorProvider,
        OdysseyActionsProvider,
        WorkspacesProvider,
        FileSearchProvider,
        ClipboardProvider,
        WebSearchProvider
    ]
    // Explicit group order: results are grouped by provider before score is
    // compared, so apps lead and a busy shell-action list can't push them out.
    // Lower rank shows first. Keyed by providerId; unknown providers sort last.
    readonly property var groupRank: ({
        "applications": 0,
        "calculator": 1,
        "odyssey-actions": 2,
        "workspaces": 3,
        "files": 4,
        "clipboard": 5,
        "web": 6
    })

    function rankOf(provider): int {
        const rank = groupRank[provider.providerId]
        return rank === undefined ? 99 : rank
    }

    function search(queryText: string, limit: int): var {
        // "=" turns the palette into a calculator: that row is the only result.
        if (queryText.trim().startsWith("="))
            return CalculatorProvider.query(queryText, limit)
        const combined = []
        for (const provider of providers) {
            const providerResults = provider.query(queryText, limit)
            const rank = rankOf(provider)
            for (const result of providerResults) {
                result.groupRank = rank
                combined.push(result)
            }
        }
        combined.sort((a, b) => a.groupRank - b.groupRank
            || b.score - a.score
            || a.title.localeCompare(b.title))
        // An arithmetic answer leads and web search always trails, whatever
        // the groups above hold. The middle is trimmed to make room for both.
        const pinnedTop = combined.filter(result => result.pinTop)
        const pinnedBottom = combined.filter(result => result.pinBottom)
        const middle = combined.filter(result => !result.pinTop && !result.pinBottom)
        return pinnedTop.concat(
            middle.slice(0, Math.max(0, limit - pinnedTop.length - pinnedBottom.length)),
            pinnedBottom)
    }

    function execute(result, copyOnly, newInstance): var {
        if (result?.provider === ApplicationsProvider.providerId)
            return ApplicationsProvider.execute(result, copyOnly, newInstance)
        if (result?.provider === OdysseyActionsProvider.providerId)
            return OdysseyActionsProvider.execute(result)
        if (result?.provider === CalculatorProvider.providerId)
            return CalculatorProvider.execute(result)
        if (result?.provider === WorkspacesProvider.providerId)
            return WorkspacesProvider.execute(result)
        if (result?.provider === FileSearchProvider.providerId)
            return FileSearchProvider.execute(result)
        if (result?.provider === ClipboardProvider.providerId)
            return ClipboardProvider.execute(result)
        if (result?.provider === WebSearchProvider.providerId)
            return WebSearchProvider.execute(result)
        console.warn("Odyssey cannot execute an unknown palette provider:",
            result?.provider || "missing")
        return { handled: false }
    }
}
