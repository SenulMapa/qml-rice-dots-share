// DEPRECATED: Old widget system. Use desktop/ instead
import QtQuick
import Quickshell
import "../core"
import "../services"

/**
 * WidgetHost -- one per screen. Reads/instantiates WidgetStore's persisted
 * layout for this screen's name and lays each entry out via WidgetFrame.
 * Exposes `widgetRepeater` and `paletteLoader` so the owning WidgetLayer
 * (PanelWindow) can build its click-through mask from the SAME item
 * instances being rendered here, instead of guessing geometry twice.
 *
 * Capped at maxWidgets per screen -- WidgetLayer's mask declares that many
 * static Region slots (Quickshell's mask tree can't grow dynamically), so
 * the cap is enforced here too via WidgetStore.addWidget's return value.
 */
Item {
    id: host

    required property var screen
    readonly property int maxWidgets: 8

    readonly property bool isPrimaryScreen: HyprlandService.primaryMonitorName.length > 0
        ? HyprlandService.primaryMonitorName === (screen?.name ?? "")
        : Quickshell.screens[0] === screen

    readonly property var entries: WidgetStore.layoutFor(screen?.name ?? "").slice(0, host.maxWidgets)

    property alias widgetRepeater: repeater
    property alias paletteLoader: paletteLoader

    // WidgetStore's FileView (blockLoading: true) still resolves
    // asynchronously relative to Component.onCompleted -- measured ~1-2s
    // after startup, not the same tick -- so seeding here unconditionally
    // would race the real load() and get wiped the moment the file (or its
    // absence) actually resolves. Seed immediately if already loaded
    // (covers a second WidgetHost created after the fact, eg. a new
    // monitor), and again the moment loadedChanged fires otherwise.
    function trySeed(): void {
        if (WidgetStore.loaded)
            WidgetStore.ensureScreenSeeded(host.screen.name, host.isPrimaryScreen)
    }
    Component.onCompleted: host.trySeed()
    Connections {
        target: WidgetStore
        function onLoadedChanged(): void { host.trySeed() }
    }

    Repeater {
        id: repeater
        model: host.entries

        WidgetFrame {
            required property var modelData
            screenName: host.screen?.name ?? ""
            entry: modelData
            screenWidth: host.width
            screenHeight: host.height
        }
    }

    Loader {
        id: paletteLoader
        active: WidgetStore.editMode
        x: Theme.space4
        y: Theme.space4
        sourceComponent: EditPalette {
            screenName: host.screen.name
        }
    }
}
