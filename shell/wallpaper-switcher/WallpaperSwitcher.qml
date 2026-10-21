import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import "../core"
import "../components"
import "../services"

/**
 * WallpaperSwitcher -- one per screen (per-screen PanelWindow pattern).
 * Quick lightweight overlay opened by Super+W for fast wallpaper selection.
 * Shows horizontal strip of thumbnails at bottom-center of focused monitor.
 *
 * Design: bottom-centered, landscape thumbnails on DP-1, portrait on rotated
 * HDMI-A-1. Current wallpaper preselected and scrolled into view.
 *
 * Behavior:
 * - Left/Right (h/l, mouse wheel) move selection
 * - Typing filters by filename (search line appears only when typing)
 * - Enter applies to that monitor; Shift+Enter applies to all monitors
 * - Esc / click-outside closes
 * - Hover previews nothing live (no wallpaper change until Enter)
 */
PanelWindow {
    id: window

    readonly property var monitor: Hyprland.monitorFor(screen)
    property string filterText: ""
    property int currentIndex: 0
    property bool isOpen: false
    property bool showAnimated: false

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "qml-rice:wallpaper-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Mapped only while open or still fading out on close -- matches how
    // island/Island.qml gates `visible` on its own open/animating state
    // rather than always mapping the surface.
    visible: isOpen || closing
    property bool closing: false

    anchors { bottom: true; left: true; right: true }
    implicitHeight: Theme.u(5.5)

    // Input mask: track the switcher panel for click input. A single
    // top-level Region has nothing to combine with, so `intersection` is
    // left at its default (there is no "Replace" value -- see
    // island/Island.qml's own top-level mask Region for the same pattern).
    mask: Region {
        item: switcherPanel
    }

    Item {
        id: switcherPanel
        x: (parent.width - width) / 2
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.u(0.9)
        width: Math.min(parent.width - Theme.u(2), Theme.u(20))
        height: Theme.u(3.2)

        // Fade lives on the content Item, not the window (PanelWindow has no
        // `opacity` -- see window.visible above for how the surface itself
        // is mapped/unmapped instead).
        opacity: window.isOpen ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: Animations.normal
                easing.type: Animations.standardEase
                onRunningChanged: if (!running && !window.isOpen)
                    window.closing = false
            }
        }

        Surface {
            anchors.fill: parent
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.u(0.5)
            spacing: Theme.u(0.3)

            // Section toggle header: "Stills · Animated" with active emphasized
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.u(0.5)
                spacing: Theme.u(0.2)

                Text {
                    text: "Stills"
                    color: !window.showAnimated ? Theme.surfaceText : Theme.surfaceVariantText
                    font.family: Config.appearance.displayFontFamily
                    font.pixelSize: Theme.textSmall
                    font.weight: !window.showAnimated ? Font.DemiBold : Font.Normal
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: window.showAnimated = false
                    }
                }

                Text {
                    text: "·"
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.textSmall
                }

                Text {
                    text: "Animated"
                    color: window.showAnimated ? Theme.surfaceText : Theme.surfaceVariantText
                    font.family: Config.appearance.displayFontFamily
                    font.pixelSize: Theme.textSmall
                    font.weight: window.showAnimated ? Font.DemiBold : Font.Normal
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: window.showAnimated = true
                    }
                }

                Item { Layout.fillWidth: true }
            }

            // Search text appears only when typing (no background, plain text)
            Item {
                id: searchContainer
                Layout.fillWidth: true
                Layout.preferredHeight: filterText.length > 0 ? Theme.u(0.8) : 0
                visible: filterText.length > 0
                clip: true

                RowLayout {
                    anchors.fill: parent
                    spacing: Theme.space1

                    Text {
                        text: "󰍉"
                        color: Theme.primary
                        font.family: Config.appearance.monoFontFamily
                        font.pixelSize: Theme.iconSmall
                    }

                    TextInput {
                        id: searchInput
                        Layout.fillWidth: true
                        text: filterText
                        color: Theme.surfaceText
                        selectionColor: Theme.primaryContainer
                        selectedTextColor: Theme.primaryContainerText
                        font.family: Config.appearance.displayFontFamily
                        font.pixelSize: Theme.textSmall
                        verticalAlignment: TextInput.AlignVCenter
                        cursorVisible: true
                        onTextChanged: filterText = text

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Escape) {
                                window.close()
                                event.accepted = true
                            } else if (event.key === Qt.Key_Return
                                    || event.key === Qt.Key_Enter) {
                                applyCurrentWallpaper(event.modifiers & Qt.ShiftModifier)
                                event.accepted = true
                            }
                        }
                    }
                }
            }

            // Thumbnail strip (thumbnails follow monitor aspect ratio)
            ListView {
                id: thumbnailList
                Layout.fillWidth: true
                Layout.fillHeight: true
                orientation: ListView.Horizontal
                spacing: Theme.u(0.4)
                clip: true

                model: filteredWallpapers
                currentIndex: window.currentIndex

                // ListView has no `availableHeight` -- it's just this
                // Layout.fillHeight item's own height.
                readonly property real thumbHeight: Math.min(Theme.u(2.6), height)
                readonly property real aspectRatio: window.screen ? (window.screen.width / window.screen.height) : 1.0

                delegate: Item {
                    id: thumbDelegate
                    width: thumbnailList.thumbHeight * thumbnailList.aspectRatio
                    height: thumbnailList.thumbHeight

                    scale: ListView.isCurrentItem ? 1.0 : 0.86
                    opacity: ListView.isCurrentItem ? 1.0 : 0.55
                    Behavior on scale { NumberAnimation { duration: Animations.normal; easing.type: Animations.emphasizedEase } }
                    Behavior on opacity { NumberAnimation { duration: Animations.normal; easing.type: Animations.emphasizedEase } }

                    ClippingRectangle {
                        anchors.fill: parent
                        radius: Theme.radiusSmall

                        Image {
                            anchors.fill: parent
                            source: modelData.thumbnailSource || (modelData.isVideo ? "" : modelData.source)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            sourceSize: Qt.size(parent.width * 2, parent.height * 2)
                        }
                    }

                    // Selection underline (only for current item)
                    Rectangle {
                        visible: ListView.isCurrentItem
                        x: (parent.width - width) / 2
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Theme.u(-0.15)
                        width: parent.width * 0.7
                        height: Theme.u(0.12)
                        radius: Theme.u(0.06)
                        color: Theme.primary
                        Behavior on opacity { NumberAnimation { duration: Animations.normal } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            window.currentIndex = index
                            applyCurrentWallpaper(false)
                        }
                    }
                }

                onCurrentIndexChanged: {
                    if (window.isOpen)
                        positionViewAtIndex(currentIndex, ListView.Center)
                }
            }
        }

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                if (window.filterText.length > 0) {
                    window.filterText = ""
                    event.accepted = true
                } else {
                    window.close()
                    event.accepted = true
                }
            } else if (event.key === Qt.Key_Tab) {
                window.showAnimated = !window.showAnimated
                window.currentIndex = window.findCurrentWallpaperIndex()
                event.accepted = true
            } else if (event.key === Qt.Key_Left || (event.text === "h")) {
                moveSelection(-1)
                event.accepted = true
            } else if (event.key === Qt.Key_Right || (event.text === "l")) {
                moveSelection(1)
                event.accepted = true
            } else if (event.key === Qt.Key_Return
                    || event.key === Qt.Key_Enter) {
                applyCurrentWallpaper(event.modifiers & Qt.ShiftModifier)
                event.accepted = true
            } else if (event.key === Qt.Key_Backspace) {
                if (window.filterText.length > 0) {
                    window.filterText = window.filterText.slice(0, -1)
                    event.accepted = true
                }
            } else if (event.text.length === 1
                    && !event.text.match(/^[\n\r\t\x1b]$/)) {
                // Start or continue filtering
                window.filterText += event.text
                searchInput.forceActiveFocus()
                event.accepted = true
            }
        }

        // Item/FocusScope has no onWheelMoved signal -- wheel input comes
        // through a WheelHandler, same primitive as
        // dashboard/components/Carousel.qml's horizontal scroller.
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                moveSelection(event.angleDelta.y > 0 ? -1 : 1)
            }
        }
    }

    readonly property var allFiltered:
        WallpaperService.filterWallpapers(filterText)

    readonly property var filteredWallpapers: allFiltered.filter(w =>
        window.showAnimated ? w.isAnimated : !w.isAnimated)

    readonly property int animatedCount: WallpaperService.wallpapers.filter(w => w.isAnimated).length

    onFilterTextChanged: {
        // When filter changes, reset index to first result or current wallpaper if visible
        const newIndex = findCurrentWallpaperIndex()
        currentIndex = newIndex
    }

    function moveSelection(delta: int): void {
        if (filteredWallpapers.length === 0)
            return
        currentIndex = (currentIndex + delta + filteredWallpapers.length)
            % filteredWallpapers.length
    }

    function applyCurrentWallpaper(applyToAll: bool): void {
        if (currentIndex < 0 || currentIndex >= filteredWallpapers.length)
            return
        const wallpaper = filteredWallpapers[currentIndex]
        if (applyToAll) {
            // Apply to all connected monitors: generate comma-separated list
            const allMonitorNames = HyprlandService.connectedMonitors
                .map(m => m.name)
                .filter(n => n)
                .join(",")
            WallpaperService.applyWallpaper(wallpaper.path, allMonitorNames)
        } else {
            WallpaperService.applyWallpaper(wallpaper.path, monitor.name)
        }
        close()
    }

    function open(): void {
        closing = false
        isOpen = true
        filterText = ""
        // Default to the section containing current wallpaper
        const current = WallpaperService.wallpapers.find(w => w.path === WallpaperService.currentWallpaper)
        if (current)
            showAnimated = current.isAnimated
        currentIndex = findCurrentWallpaperIndex()
        Qt.callLater(() => {
            switcherPanel.focus = true
            switcherPanel.forceActiveFocus()
        })
    }

    function close(): void {
        if (!isOpen)
            return
        // Keep the surface mapped for the fade-out (see switcherPanel's
        // opacity Behavior above, which clears `closing` when it finishes).
        closing = true
        isOpen = false
        filterText = ""
    }

    function findCurrentWallpaperIndex(): int {
        for (let i = 0; i < filteredWallpapers.length; ++i) {
            if (filteredWallpapers[i].path === WallpaperService.currentWallpaper)
                return i
        }
        return Math.max(0, Math.min(currentIndex, filteredWallpapers.length - 1))
    }

}
