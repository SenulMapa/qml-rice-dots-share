import QtQuick
import "../core"

/**
 * Surface - the shared panel look: the island, its satellites, previews.
 *
 * Upstream drew a flat translucent fill with an outline. The design layer adds
 * three devices, none of them translucency, which is why they cost nothing on
 * an integrated GPU (this also runs on a UHD 620):
 *   - a top-down light falloff
 *   - a 1 px sheen along the top edge, inset from the corners so a rounded
 *     corner never slices it
 *   - a hairline border
 *
 * `color` and `border.color` stay plain properties so use sites can keep
 * overriding them: the island tints both for the power-profile pulse. A
 * `gradient` on this Rectangle would silently take precedence over that colour,
 * so the falloff lives on a child overlay instead. A component's own children
 * are created before use-site children, so the decoration always sits beneath
 * content.
 */
Rectangle {
    id: root
    // Solid, per the owner (13 Sep 2026): no translucency, no light falloff,
    // no sheen. One opaque wallpaper-derived fill.
    color: Theme.surfaceContainer
    border.width: 0
    radius: Theme.radiusLarge

    Behavior on color { ColorAnimation { duration: Animations.normal } }
}
