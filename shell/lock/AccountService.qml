pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// ported from impasto services/AccountService.qml, verbatim except: dropped
// the SettingsService.userName/userAvatar override lookup -- this shell has
// no settings store field for a lock-screen name/avatar override (DeskSettings
// has no userName/userAvatar; adding one was out of scope for this port), so
// `name`/`avatar` read straight from the system value instead of falling
// back to it. Quickshell.shellPath -> Quickshell.shellDir, this shell's own
// convention (see e.g. services/SessionService.qml's helperPath).
Singleton {
    id: root

    readonly property string script: Quickshell.shellDir + "/scripts/account.py"

    property string user: ""
    property string name: ""
    property string avatar: ""

    // Drawn when there is no picture: at most two initials.
    readonly property string initials: {
        const words = root.name.trim().split(/\s+/).filter(word => word !== "")
        if (words.length === 0)
            return "?"
        if (words.length === 1)
            return words[0].slice(0, 1).toUpperCase()
        return (words[0].slice(0, 1) + words[words.length - 1].slice(0, 1)).toUpperCase()
    }

    readonly property Process reader: Process {
        command: [root.script, "get"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                if (!text || text.trim() === "")
                    return
                try {
                    const report = JSON.parse(text)
                    root.user = report.user ?? ""
                    root.name = report.name ?? root.user
                    root.avatar = report.avatar ?? ""
                } catch (error) {
                    console.warn("qml-rice AccountService: cannot parse the account:", error)
                }
            }
        }
    }
}
