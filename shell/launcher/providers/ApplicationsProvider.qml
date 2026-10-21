pragma Singleton
import QtQuick
import "../../applications"
import "../../services"

QtObject {
    readonly property string providerId: "applications"
    readonly property string displayName: "Applications"
    readonly property int priority: 80

    function query(queryText: string, limit: int): var {
        const entries = ApplicationService.find(queryText)
        const results = []
        const bounded = Math.min(limit, entries.length)
        const emptyQuery = queryText.trim().length === 0
        for (let i = 0; i < bounded; ++i) {
            const entry = entries[i]
            const category = ApplicationService.primaryCategory(entry)
            const recent = emptyQuery && ApplicationService.isRecent(entry)
            // An app that is already open is marked "Open": Enter focuses its
            // window, Shift+Enter starts a new instance (see execute below).
            const running = RunningApps.groupForEntry(entry) !== null
            results.push({
                key: `application:${entry.id}`,
                provider: providerId,
                group: displayName,
                kind: "application",
                actionId: "launch-application",
                title: entry.name,
                subtitle: entry.comment || entry.genericName || "Launch application",
                icon: entry.icon || "",
                iconKind: "theme",
                badge: running ? "Open" : recent ? "Recent" : (category || "Application"),
                running: running,
                score: (emptyQuery ? 600 : 900) - i,
                application: entry,
                enabled: true
            })
        }
        return results
    }

    // Enter focuses a running app. Shift+Enter (newInstance) always launches.
    function execute(result, copyOnly, newInstance): var {
        if (!result?.application)
            return { handled: false }
        const group = result.running && !newInstance
            ? RunningApps.groupForEntry(result.application) : null
        if (group) {
            RunningApps.focus(group)
            return { handled: true, dismiss: true }
        }
        ApplicationService.launch(result.application)
        return { handled: true, dismiss: true }
    }
}
