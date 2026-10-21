import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import "../components"
import "../core"
import "../services"

Item {
    id: root

    property var monitor
    property bool showAnimated: false
    readonly property var allFiltered:
        WallpaperService.filterWallpapers(searchInput.text)
    readonly property var filteredWallpapers: allFiltered.filter(w =>
        root.showAnimated ? w.isAnimated : !w.isAnimated)
    readonly property int animatedCount: WallpaperService.wallpapers.filter(w => w.isAnimated).length
    readonly property int stillsCount: WallpaperService.wallpapers.filter(w => !w.isAnimated).length
    readonly property string monitorName: monitor?.name || ""

    // Ink (Config.appearance.ink): a filmstrip instead of the grid. The
    // selected thumb is a MotionValue-driven scale, the strip slides on a
    // spring, and "Set wallpaper" applies the selected entry. The grid branch
    // stays for ink off.
    readonly property bool ink: Config.appearance.ink
    property int selectedIndex: 0
    property int captionIndex: 0
    readonly property int thumbW: 200
    readonly property int thumbGap: 24

    Component.onCompleted: {
        // Default to the section containing current wallpaper
        const current = WallpaperService.wallpapers.find(w => w.path === WallpaperService.currentWallpaper)
        if (current)
            root.showAnimated = current.isAnimated
    }

    function activateImage(image): void {
        WallpaperService.applyWallpaper(image.path, monitorName)
    }

    // Ink: Left/Right move the filmstrip selection. Setting selectedIndex is
    // the same path a thumb click takes, so the strip springs identically.
    function stepSelection(delta): void {
        const last = root.filteredWallpapers.length - 1
        if (last < 0)
            return
        root.selectedIndex = Math.max(0, Math.min(last, root.selectedIndex + delta))
    }

    // Keyboard focus while the page is open, so the arrow keys reach it.
    focus: visible

    Keys.onLeftPressed: event => {
        if (!root.ink)
            return
        root.stepSelection(-1)
        event.accepted = true
    }
    Keys.onRightPressed: event => {
        if (!root.ink)
            return
        root.stepSelection(1)
        event.accepted = true
    }

    // Select the active wallpaper in the visible section, or the first one.
    function syncSelection(): void {
        const at = root.filteredWallpapers.findIndex(w => w.path === WallpaperService.currentWallpaper)
        root.selectedIndex = at >= 0 ? at : 0
    }

    onShowAnimatedChanged: syncSelection()
    onFilteredWallpapersChanged: {
        if (root.selectedIndex >= root.filteredWallpapers.length)
            root.selectedIndex = Math.max(0, root.filteredWallpapers.length - 1)
    }
    onSelectedIndexChanged: captionSwap.restart()

    onVisibleChanged: {
        if (visible) {
            if (root.ink)
                Qt.callLater(() => root.forceActiveFocus())
            // Reset to current wallpaper's section when opening
            const current = WallpaperService.wallpapers.find(w => w.path === WallpaperService.currentWallpaper)
            if (current)
                root.showAnimated = current.isAnimated
            if (Config.wallpaper.refreshOnOpen)
                WallpaperService.refresh()
            if (root.ink)
                root.syncSelection()
        }
    }

    // Caption crossfade: the old caption fades out, the new one fades in.
    SequentialAnimation {
        id: captionSwap
        NumberAnimation { target: captionBox; property: "opacity"; to: 0; duration: Theme.microMs; easing.type: Easing.OutCubic }
        ScriptAction { script: root.captionIndex = root.selectedIndex }
        NumberAnimation { target: captionBox; property: "opacity"; to: 1; duration: Theme.microMs; easing.type: Easing.OutCubic }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.space2

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 42
            spacing: Theme.space2

            ColumnLayout {
                // Nested layouts are expansive by default. Keep the heading at
                // its intended width so the search field owns the flexible
                // space in this row.
                Layout.fillWidth: false
                Layout.preferredWidth: 190
                spacing: 0
                Text {
                    text: "Wallpaper"
                    color: root.ink ? Theme.t1 : AdaptiveColor.glassText
                    font.family: root.ink ? Theme.fontUi : Config.appearance.displayFontFamily
                    font.pixelSize: root.ink ? 20 : Theme.textTitle + 6
                    font.weight: root.ink ? Font.DemiBold : Font.Normal
                }
                Text {
                    visible: !root.ink
                    Layout.fillWidth: true
                    text: WallpaperService.statusLabel
                    color: WallpaperService.errorMessage.length > 0
                        ? Theme.warning : AdaptiveColor.glassTextDim
                    elide: Text.ElideRight
                    font.family: Config.appearance.fontFamily
                    font.pixelSize: 9
                }
            }

            RowLayout {
                // Ink replaces this header toggle with the text tabs below.
                visible: !root.ink
                Layout.fillWidth: false
                spacing: Theme.space2

                Text {
                    text: "Stills"
                    color: !root.showAnimated ? AdaptiveColor.glassText : AdaptiveColor.glassTextDim
                    font.family: Config.appearance.displayFontFamily
                    font.pixelSize: 11
                    font.weight: !root.showAnimated ? Font.DemiBold : Font.Normal
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.showAnimated = false
                    }
                }

                Text {
                    text: "·"
                    color: AdaptiveColor.glassTextDim
                    font.pixelSize: 11
                }

                Text {
                    text: "Animated " + root.animatedCount
                    color: root.showAnimated ? AdaptiveColor.glassText : AdaptiveColor.glassTextDim
                    font.family: Config.appearance.displayFontFamily
                    font.pixelSize: 11
                    font.weight: root.showAnimated ? Font.DemiBold : Font.Normal
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.showAnimated = true
                    }
                }
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                visible: root.width > 520
                // Keep the hidden item out of sizing entirely; the compact
                // header deliberately has no search control.
                Layout.fillWidth: false
                Layout.minimumWidth: 0
                Layout.maximumWidth: visible ? Number.POSITIVE_INFINITY : 0
                Layout.preferredWidth: visible ? 228 : 0
                Layout.preferredHeight: 34
                radius: root.ink ? Theme.rCtl : Theme.radiusMedium
                color: root.ink ? Theme.inkRaised : Qt.alpha(Theme.surfaceContainerHigh, 0.62)
                // Keep every search child inside the width assigned by the
                // header layout, including during layout/visibility changes.
                clip: true
                border.width: 0

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.space3
                    anchors.rightMargin: Theme.space3
                    spacing: Theme.space2
                    Text {
                        text: "󰍉"
                        color: AdaptiveColor.glassTextDim
                        font.family: Config.appearance.monoFontFamily
                        font.pixelSize: 13
                    }
                    TextInput {
                        id: searchInput
                        Layout.fillWidth: true
                        color: root.ink ? Theme.t1 : AdaptiveColor.glassText
                        selectionColor: Theme.primaryContainer
                        selectedTextColor: Theme.primaryContainerText
                        font.family: root.ink ? Theme.fontUi : Config.appearance.fontFamily
                        font.pixelSize: root.ink ? 13 : 11
                        clip: true

                        Text {
                            visible: searchInput.text.length === 0
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Search wallpapers"
                            color: root.ink ? Theme.t3 : AdaptiveColor.glassTextDim
                            font: searchInput.font
                        }
                    }
                }
            }

            TextButton {
                Layout.preferredHeight: 34
                Layout.preferredWidth: 68
                // Refresh is a mouse utility action: retain the ordinary
                // pressed/hover response without a persistent focus outline
                // or a loading-label swap that makes the header flicker.
                showFocusIndicator: false
                text: "Refresh"
                onClicked: WallpaperService.refresh()
            }

            // Ink: applies the filmstrip's selected wallpaper through the same
            // activateImage path the grid cards use.
            Rectangle {
                visible: root.ink
                Layout.preferredHeight: 36
                Layout.preferredWidth: setLabel.implicitWidth + Theme.space5 * 2
                radius: height / 2
                color: setHover.hovered ? Qt.alpha(Theme.fillOn, 0.88) : Theme.fillOn
                enabled: root.filteredWallpapers.length > 0

                Text {
                    id: setLabel
                    anchors.centerIn: parent
                    text: "Set wallpaper"
                    color: Theme.glyphOn
                    font.family: Theme.fontUi
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }

                HoverHandler { id: setHover }
                TapHandler {
                    onTapped: {
                        const image = root.filteredWallpapers[root.selectedIndex]
                        if (image)
                            root.activateImage(image)
                    }
                }
            }
        }

        // Ink: plain text tabs, 2px underline on the active one.
        RowLayout {
            visible: root.ink
            Layout.fillWidth: true
            Layout.topMargin: 12
            spacing: 24

            Repeater {
                model: [
                    { label: "Animated", animated: true },
                    { label: "Still", animated: false }
                ]

                delegate: Item {
                    required property var modelData
                    readonly property bool active: root.showAnimated === modelData.animated
                    implicitWidth: tabLabel.implicitWidth
                    implicitHeight: tabLabel.implicitHeight + Theme.space2

                    Text {
                        id: tabLabel
                        anchors.left: parent.left
                        anchors.top: parent.top
                        text: modelData.label
                        color: parent.active ? Theme.t1 : Theme.t3
                        font.family: Theme.fontUi
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 2
                        radius: 1
                        color: Theme.fillOn
                        transformOrigin: Item.Left
                        scale: parent.active ? 1 : 0
                        Behavior on scale { NumberAnimation { duration: Theme.microMs; easing.type: Easing.OutCubic } }
                    }

                    TapHandler { onTapped: root.showAnimated = modelData.animated }
                }
            }

            Item { Layout.fillWidth: true }
        }

        // Ink filmstrip. Thumbs are 200x112 at 24px gaps; the strip slides on
        // a spring so the selected thumb centres in the view.
        Item {
            id: inkView
            visible: root.ink
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: Theme.space4
            clip: true

            readonly property real stripTarget: width / 2
                - (root.selectedIndex * (root.thumbW + root.thumbGap) + root.thumbW / 2)

            MotionValue {
                id: stripMotion
                unit: "px"
                omega: Motion.presetSmooth().omega
                zeta: Motion.presetSmooth().zeta
                target: inkView.stripTarget
            }

            Item {
                id: strip
                width: parent.width
                height: 112
                anchors.verticalCenter: parent.verticalCenter
                x: stripMotion.value

                Repeater {
                    model: root.ink ? root.filteredWallpapers : []

                    delegate: ClippingRectangle {
                        id: thumb
                        required property var modelData
                        required property int index
                        readonly property bool sel: index === root.selectedIndex

                        x: index * (root.thumbW + root.thumbGap)
                        y: 0
                        width: root.thumbW
                        height: 112
                        radius: Theme.rCtl
                        color: Theme.inkRaised
                        opacity: thumbOpacity.value
                        scale: thumbScale.value

                        MotionValue {
                            id: thumbScale
                            unit: "ratio"
                            omega: Motion.presetSnappy().omega
                            zeta: Motion.presetSnappy().zeta
                            target: thumb.sel ? 1.3 : 0.9
                        }

                        MotionValue {
                            id: thumbOpacity
                            unit: "ratio"
                            omega: Motion.presetSnappy().omega
                            zeta: Motion.presetSnappy().zeta
                            target: thumb.sel ? 1 : 0.5
                        }

                        Image {
                            anchors.fill: parent
                            source: thumb.modelData.thumbnailSource
                                || (thumb.modelData.isVideo ? "" : thumb.modelData.source)
                            asynchronous: true
                            cache: true
                            fillMode: Image.PreserveAspectCrop
                            sourceSize.width: 420
                            sourceSize.height: 250
                        }

                        TapHandler { onTapped: root.selectedIndex = thumb.index }
                    }
                }
            }

            // Edge fades so the strip dissolves into the ink on both sides.
            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 120
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Theme.ink }
                    GradientStop { position: 1; color: "transparent" }
                }
            }
            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 120
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: Theme.ink }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: !WallpaperService.loading && root.filteredWallpapers.length === 0
                text: {
                    if (searchInput.text.length > 0)
                        return "No matching wallpapers"
                    if (root.showAnimated && root.animatedCount === 0)
                        return "No animated wallpapers"
                    return "No wallpapers discovered"
                }
                color: Theme.t3
                font.family: Theme.fontUi
                font.pixelSize: 14
            }
        }

        // Ink caption under the strip: name and kind, crossfaded on change.
        ColumnLayout {
            id: captionBox
            visible: root.ink
            Layout.fillWidth: true
            Layout.bottomMargin: Theme.space2
            spacing: Theme.space1
            readonly property var shown: root.filteredWallpapers[root.captionIndex] ?? null

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: captionBox.shown?.name ?? ""
                color: Theme.t1
                elide: Text.ElideRight
                font.family: Theme.fontUi
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: captionBox.shown
                    ? (captionBox.shown.isAnimated ? "Animated" : "Still")
                        + (captionBox.shown.path === WallpaperService.currentWallpaper ? ", active" : "")
                    : ""
                color: Theme.t2
                elide: Text.ElideRight
                font.family: Theme.fontUi
                font.pixelSize: 13
                font.weight: Font.Medium
            }
        }

        Squircle {
            visible: WallpaperService.backendState !== "ready"
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? 52 : 0
            radius: Theme.radiusMedium
            color: Qt.alpha(Theme.surfaceContainerHigh, 0.72)
            borderWidth: 1
            borderColor: WallpaperService.errorMessage.length > 0 ? Theme.warning
                : Qt.alpha(Theme.outlineVariant, 0.45)
            RowLayout {
                anchors.fill: parent; anchors.margins: Theme.space2; spacing: Theme.space2
                ColumnLayout { Layout.fillWidth: true; spacing: 1
                    Text { text: "Wallpaper setup"; color: AdaptiveColor.glassText; font.family: Config.appearance.fontFamily; font.pixelSize: 10; font.weight: Font.DemiBold; elide: Text.ElideRight }
                    Text { Layout.fillWidth: true; text: WallpaperService.backendDetail; color: AdaptiveColor.glassTextDim; font.family: Config.appearance.fontFamily; font.pixelSize: 9; elide: Text.ElideRight }
                }
                TextButton { visible: WallpaperService.backendState !== "ready"; text: "Check again"; onClicked: WallpaperService.retry() }
            }
        }

        Rectangle {
            visible: !root.ink
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Theme.radiusLarge
            color: Qt.alpha(Theme.surfaceContainerLow, 0.48)
            border.width: 1
            border.color: Qt.alpha(Theme.outlineVariant, 0.32)
            clip: true

            GridView {
                id: gallery
                anchors.fill: parent
                anchors.margins: Theme.space2
                clip: true
                model: root.filteredWallpapers
                cellWidth: width / Config.wallpaper.galleryColumns
                cellHeight: Config.wallpaper.cardHeight
                boundsBehavior: Flickable.StopAtBounds
                keyNavigationWraps: true

                delegate: Item {
                    required property var modelData
                    width: gallery.cellWidth
                    height: gallery.cellHeight

                    WallpaperCard {
                        anchors.fill: parent
                        anchors.margins: 4
                        wallpaper: modelData
                        current: modelData.path === WallpaperService.currentWallpaper
                        applying: modelData.path === WallpaperService.pendingWallpaper
                        currentLabel: "ACTIVE"
                        onActivated: root.activateImage(modelData)
                    }
                }
            }

            ColumnLayout {
                visible: !WallpaperService.loading
                    && root.filteredWallpapers.length === 0
                anchors.centerIn: parent
                spacing: Theme.space2
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "󰸉"
                    color: AdaptiveColor.glassTextDim
                    font.family: Config.appearance.monoFontFamily
                    font.pixelSize: 28
                }
                Text {
                    text: {
                        if (searchInput.text.length > 0)
                            return "No matching wallpapers"
                        if (root.showAnimated && root.animatedCount === 0)
                            return "No animated wallpapers"
                        return "No wallpapers discovered"
                    }
                    color: AdaptiveColor.glassTextDim
                    font.family: Config.appearance.fontFamily
                    font.pixelSize: Theme.textBody
                }
            }
        }
    }
}
