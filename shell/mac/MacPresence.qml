pragma Singleton
import QtQuick
import "../core"

/**
 * MacPresence -- the crossfade for a switch between the pill and mac
 * presentations (spec section 2: 220 ms, or instant under reduced motion).
 *
 *   wanted   Config.appearance.macStyle, the setting itself.
 *   mounted  whether the mac root stays loaded (shell.qml Loader). It stays
 *            true through the fade-out, so the mac surfaces can ramp down
 *            before they unload. Switching to mac mounts it at once.
 *   level    1 while mac is wanted, 0 otherwise, animated over fadeMs. Every
 *            mac window multiplies its content opacity by it.
 *
 * The pill side is not ramped here: its content is not under one root. The
 * mac side fades, and the pill appears as the mac side leaves.
 */
QtObject {
    id: root

    readonly property bool wanted: Config.appearance.macStyle
    readonly property bool instant: Config.appearance.reducedMotion
    readonly property int fadeMs: Config.animations.normal

    property bool mounted: wanted
    property real level: wanted ? 1 : 0

    Behavior on level {
        enabled: !root.instant
        NumberAnimation { duration: root.fadeMs; easing.type: Easing.OutCubic }
    }

    onWantedChanged: {
        if (wanted) {
            retireTimer.stop()
            root.mounted = true
        } else if (root.instant) {
            root.mounted = false
        } else {
            retireTimer.restart()
        }
    }

    // Unmounts the mac root once the fade-out has finished.
    property Timer retireTimer: Timer {
        interval: root.fadeMs + 20
        onTriggered: root.mounted = false
    }
}
