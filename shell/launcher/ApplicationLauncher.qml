import QtQuick
import "../services"

LauncherView {
    provider: CommandPaletteService
    placeholderText: "Search apps"
    emptyText: "No matches"

    onVisibleChanged: {
        if (visible) {
            ClipboardService.refresh()
        }
    }
}
