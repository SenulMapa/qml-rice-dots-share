import QtQuick
import "../core"
import "../services"
import "../components"

Squircle {
    id: root

    property color accent: AdaptiveColor.activeFill
    property bool interactive: true
    signal activated()

    radius: Theme.radiusLarge
    // De-bento: at rest a card is fully transparent with no border. Zones
    // separate by whitespace alone. An interactive card gets a very faint
    // hover wash that fades in/out -- nothing else, ever, at rest.
    color: cardHover.hovered && interactive
        ? Qt.alpha(AdaptiveColor.glassText, 0.05)
        : "transparent"
    borderWidth: 0

    HoverHandler { id: cardHover; enabled: root.interactive }
    TapHandler {
        enabled: root.interactive
        onTapped: root.activated()
    }

    Behavior on color { ColorAnimation { duration: Animations.fast } }
}
