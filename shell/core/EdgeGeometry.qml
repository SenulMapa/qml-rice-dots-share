pragma Singleton
import QtQuick

/**
 * EdgeGeometry -- decides which side(s) of a given screen are "outer" edges
 * (not shared with an adjacent screen), from the live screen list, instead
 * of hard-coding output names. Used by services/VolumeEdge (edge/) to place
 * its invisible scroll strips only on outer edges, never on an inner
 * boundary the cursor has to cross between two monitors.
 *
 * A screen's left edge (screen.x) is "outer" unless some OTHER screen's
 * right edge lands on exactly the same x AND the two screens overlap in Y
 * (i.e. they are actually side-by-side there, not just coincidentally
 * sharing an x coordinate on unrelated rows). Symmetric check for the
 * right edge. Works for rotated monitors too: ShellScreen.width/height
 * already report the POST-transform logical size (Qt/Wayland convention),
 * so a 90°-rotated 1920x1080 output showing up as 1080x1920 needs no
 * special-casing here.
 */
QtObject {
    id: root

    function _overlapsY(a, b): bool {
        return a.y < b.y + b.height && b.y < a.y + a.height
    }

    /**
     * Returns an array containing zero, one or both of "left"/"right" for
     * `screen`, given the full `screens` list (Quickshell.screens). A
     * single-monitor setup gets both edges; two side-by-side monitors each
     * get only their true outer edge; three-plus in a row get outer edges
     * only on the two ends.
     */
    function outerEdgesFor(screen, screens): var {
        if (!screen)
            return []

        const left = screen.x
        const right = screen.x + screen.width
        let hasLeftNeighbor = false
        let hasRightNeighbor = false

        for (const other of (screens || [])) {
            if (!other || other === screen)
                continue
            if (!root._overlapsY(screen, other))
                continue
            if (other.x + other.width === left)
                hasLeftNeighbor = true
            if (other.x === right)
                hasRightNeighbor = true
        }

        const edges = []
        if (!hasLeftNeighbor)
            edges.push("left")
        if (!hasRightNeighbor)
            edges.push("right")
        return edges
    }

    /**
     * Flattens outerEdgesFor() across every screen into one array of
     * {screen, edge} instances, suitable as a Quickshell `Variants.model`.
     */
    function instancesFor(screens): var {
        const result = []
        for (const s of (screens || [])) {
            for (const edge of root.outerEdgesFor(s, screens))
                result.push({ screen: s, edge: edge })
        }
        return result
    }
}
