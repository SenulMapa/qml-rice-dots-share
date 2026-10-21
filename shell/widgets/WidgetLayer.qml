// DEPRECATED: Old widget system. Use desktop/ instead
import QtQuick
import Quickshell
import Quickshell.Wayland
import "../services"

/**
 * WidgetLayer -- one per screen (see shell.qml's Variants over
 * Quickshell.screens), a background-layer surface for the Pixel-style
 * desktop widgets. Modelled directly on end4-ii's
 * modules/ii/background/Background.qml (Bottom layer, exclusionMode:
 * Ignore, transparent, full-screen anchors) but far lighter: no wallpaper
 * rendering here (WallpaperService/awww already owns that), and the click
 * mask is built from the SAME WidgetFrame/EditPalette item instances
 * WidgetHost renders, so empty desktop space is always click-through and
 * only the widgets (and, in edit mode, the add-palette) are hit-testable.
 */
PanelWindow {
    id: window

    // screen is assigned by the instantiation site (shell.qml's Variants),
    // exactly like island/Island.qml -- neither component declares its own
    // `modelData`; the Variants delegate wrapper does.
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "qml-rice:widgets"
    // WlrKeyboardFocus.None (the original value here) means this layer can
    // NEVER receive keyboard input, full stop -- not just "doesn't grab
    // focus unsolicited". Ported widgets that need typed input (see
    // widgets/TodoWidget.qml's add-task field) would silently eat clicks
    // on their TextInput and never accept a single keystroke. OnDemand is
    // the layer-shell mode made for exactly this: the layer stays out of
    // the way until something inside it (a focused TextInput) explicitly
    // requests active focus, then releases it again once that item loses
    // focus -- normal desktop clicks elsewhere are unaffected.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    WidgetHost {
        id: host
        anchors.fill: parent
        screen: window.screen
    }

    // Static pool of mask slots -- Quickshell's Region tree is declared,
    // not dynamically grown, so this covers host.maxWidgets (8) regardless
    // of how many are actually populated. Region.item: null contributes no
    // area (same pattern Island.qml relies on for its satellites), so
    // unused slots are exactly zero-cost/zero-area, not "whole screen
    // minus a hole".
    mask: Region {
        Region { item: host.widgetRepeater.itemAt(0); intersection: Intersection.Combine }
        Region { item: host.widgetRepeater.itemAt(1); intersection: Intersection.Combine }
        Region { item: host.widgetRepeater.itemAt(2); intersection: Intersection.Combine }
        Region { item: host.widgetRepeater.itemAt(3); intersection: Intersection.Combine }
        Region { item: host.widgetRepeater.itemAt(4); intersection: Intersection.Combine }
        Region { item: host.widgetRepeater.itemAt(5); intersection: Intersection.Combine }
        Region { item: host.widgetRepeater.itemAt(6); intersection: Intersection.Combine }
        Region { item: host.widgetRepeater.itemAt(7); intersection: Intersection.Combine }
        Region {
            item: host.paletteLoader.active ? host.paletteLoader.item : null
            intersection: Intersection.Combine
        }
    }
}
