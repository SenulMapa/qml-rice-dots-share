pragma Singleton
import QtQuick
import "../../core"
import "../../services"

QtObject {
    readonly property string providerId: "odyssey-actions"
    readonly property string displayName: "Shell actions"
    readonly property int priority: 100

    function actions(): var {
        return [
            {
                id: "switch-ui-style",
                title: "Switch UI style",
                subtitle: Config.appearance.macStyle
                    ? "Now Mac style. Switch back to the pill"
                    : "Now pill style. Switch to Mac (Tahoe) style",
                terms: "switch style ui look presentation mac macos tahoe pill island theme",
                icon: "◐",
                lucide: "layers",
                badge: "Appearance",
                enabled: true
            },
            {
                id: "open-settings",
                title: "Open settings",
                subtitle: "Appearance, palette, and integration ownership",
                terms: "settings preferences appearance theme matugen integration",
                icon: "󰒓",
                lucide: "settings",
                badge: "Navigation",
                enabled: true
            },
            {
                id: "open-clipboard",
                title: "Open clipboard",
                subtitle: "Search local text history",
                terms: "clipboard clip history copied paste",
                icon: "󰅌",
                lucide: "clipboard",
                badge: "Navigation",
                enabled: ClipboardService.available
            },
            {
                id: "open-notifications",
                title: "Open notifications",
                subtitle: "View notification history",
                terms: "notifications notification history alerts",
                icon: "󰂚",
                lucide: "bell",
                badge: "Navigation",
                enabled: true
            },
            {
                id: "toggle-dnd",
                title: NotificationService.doNotDisturb
                    ? "Turn off do not disturb" : "Turn on do not disturb",
                subtitle: "Control notification interruptions",
                terms: "dnd do not disturb notifications quiet silence",
                icon: NotificationService.doNotDisturb ? "󰂚" : "󰂛",
                lucide: NotificationService.doNotDisturb ? "bell-off" : "bell",
                badge: "Notification",
                enabled: true
            },
            {
                id: "power-saver",
                title: "Use power saver",
                subtitle: "Reduce power use and background performance",
                terms: "power saver battery profile efficiency eco",
                icon: "󰌪",
                lucide: "battery-low",
                badge: "Power",
                enabled: PowerProfileService.available
            },
            {
                id: "balanced",
                title: "Use balanced power",
                subtitle: "Balance responsiveness and energy use",
                terms: "balanced power profile normal default",
                icon: "󰾅",
                lucide: "battery-medium",
                badge: "Power",
                enabled: PowerProfileService.available
            },
            {
                id: "performance",
                title: "Use performance mode",
                subtitle: PowerProfileService.performanceAvailable
                    ? "Prioritize system performance" : "Unavailable on the current power backend",
                terms: "performance power profile fast boost",
                icon: "󰓅",
                lucide: "zap",
                badge: "Power",
                enabled: PowerProfileService.performanceAvailable
            },
            {
                id: "toggle-bluetooth",
                title: BluetoothService.enabled
                    ? "Turn Bluetooth off" : "Turn Bluetooth on",
                subtitle: BluetoothService.available
                    ? BluetoothService.detailLabel : "Bluetooth is unavailable",
                terms: "bluetooth wireless toggle enable disable devices",
                icon: BluetoothService.icon,
                lucide: BluetoothService.enabled ? "bluetooth" : "bluetooth-off",
                badge: "Bluetooth",
                enabled: BluetoothService.available && !BluetoothService.changing
            }
        ]
    }

    function matchScore(queryText: string, action): int {
        const needle = queryText.trim().toLowerCase()
        if (!needle)
            return -1
        const title = action.title.toLowerCase()
        const terms = `${title} ${action.terms}`.toLowerCase()
        if (title === needle)
            return 1200
        if (title.startsWith(needle))
            return 1100 - title.length
        const position = terms.indexOf(needle)
        if (position >= 0)
            return 1000 - position
        const tokens = needle.split(/\s+/)
        return tokens.every(token => terms.indexOf(token) >= 0) ? 900 : -1
    }

    function query(queryText: string, limit: int): var {
        const matches = []
        for (const action of actions()) {
            const score = matchScore(queryText, action)
            if (score < 0)
                continue
            matches.push({
                key: `action:${action.id}`,
                provider: providerId,
                group: displayName,
                kind: "action",
                actionId: action.id,
                title: action.title,
                subtitle: action.subtitle,
                icon: action.icon,
                lucide: action.lucide ?? "",
                iconKind: "glyph",
                badge: action.badge,
                score: score,
                enabled: action.enabled
            })
        }
        matches.sort((a, b) => b.score - a.score
            || a.title.localeCompare(b.title))
        return matches.slice(0, limit)
    }

    function execute(result): var {
        if (!result?.enabled)
            return { handled: false }
        if (result.actionId === "open-notifications")
            return { handled: true, page: "notifications" }
        if (result.actionId === "open-settings")
            return { handled: true, page: "settings" }
        if (result.actionId === "open-clipboard")
            return { handled: true, page: "clipboard" }
        if (result.actionId === "switch-ui-style")
            SettingsStore.setUiStyle(Config.appearance.macStyle ? "pill" : "mac")
        else if (result.actionId === "toggle-dnd")
            NotificationService.toggleDoNotDisturb()
        else if (result.actionId === "power-saver"
                || result.actionId === "balanced"
                || result.actionId === "performance")
            PowerProfileService.setProfileId(result.actionId)
        else if (result.actionId === "toggle-bluetooth")
            BluetoothService.toggleEnabled()
        else
            return { handled: false }
        return { handled: true, dismiss: true }
    }
}
