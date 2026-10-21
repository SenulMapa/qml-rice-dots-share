import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import "../components"
import "../core"
import "../services"

/**
 * IslandHover -- the hover pill's content: art+title | clock+date | status.
 *
 * The clock is the one thing on this pill that must actually sit on the
 * pill's horizontal centre, not just be part of a centred GROUP -- see
 * island/IslandDormant.qml's header comment for why a fill-spacer RowLayout
 * doesn't do that. IslandHoverItem's "Clock" component is anchored to
 * parent.horizontalCenter directly, same as here before this redesign.
 *
 * Everything else is now exactly two zones, not a configurable strip of
 * icons: the media block (album art flush to the pill's own left corner,
 * title/artist beside it) on the left, and ONE rounded status capsule on the
 * right holding whichever of Network/Battery/Bluetooth/etc. the order editor
 * has enabled -- Workspaces/Audio/Dnd/KeepAwake are still valid entries
 * there (SettingsStore.validHoverIslandItems), they just fold into the same
 * capsule as another glyph instead of getting their own spaced slot. Both
 * zones use the SAME `inset` for their top/bottom AND leading/trailing
 * margins, so the art's corner inset and the capsule's corner inset read as
 * one consistent margin, not two coincidentally-similar numbers.
 */
Item {
    id: root
    property var monitor
    signal controlCenterRequested(string card)
    // Ink: true only where SharedElements draws these items. The settings
    // live preview hosts this same item unshared, so it keeps its copies.
    property bool shareHosted: false
    readonly property bool inkShared: Config.appearance.ink && root.shareHosted

    // impasto card pages (DeskSettings.islandImpastoCards): each capsule
    // glyph is its own hit area (see the per-entry TapHandler in
    // statusCapsule's Repeater below) rather than one tap target for the
    // whole capsule guessing which icon was meant. Dnd/KeepAwake/
    // Workspaces have no card of their own, so a tap on those glyphs is a
    // no-op here (they previously opened the dashboard via the capsule-
    // wide tap this replaces).
    function cardForCapsuleItem(id: string): string {
        if (id === "Network" && BatteryService.available)
            return "battery"
        if (id === "Network" && NetworkService.available)
            return "wifi"
        if (id === "Bluetooth" && BluetoothService.connected)
            return "bluetooth"
        if (id === "Battery" && BatteryService.available)
            return "battery"
        if (id === "Audio" && AudioService.available)
            return "volume"
        return ""
    }

    readonly property var order: Config.island.hoverItemOrder
    readonly property bool hasMedia: order.indexOf("Media") >= 0
        && MediaService.hoverVisible
    readonly property bool hasClock: order.indexOf("Clock") >= 0
    // Everything besides Media/Clock collapses into the one status capsule.
    readonly property var capsuleOrder: root.order.filter(
        id => id !== "Media" && id !== "Clock")
    readonly property real inset: Theme.space2
    // Ink: the pill is 420x52 and nothing may draw outside it.
    clip: Config.appearance.ink

    function capsuleItemVisible(id: string): bool {
        return id === "Network" ? NetworkService.available
            : id === "Battery" ? BatteryService.available
            : id === "Bluetooth" ? BluetoothService.connected
            : id === "Audio" ? AudioService.available
            : id === "Dnd" || id === "KeepAwake" || id === "Workspaces"
    }
    readonly property bool hasCapsuleContent: root.capsuleOrder.some(
        id => root.capsuleItemVisible(id))

    // Ink: the clock is the single-line Geist text below, centred on the
    // pill. The hover item itself collapses to a point at the centre so the
    // media block's right edge (anchored to it) stops at the pill's centre.
    IslandHoverItem {
        id: hoverClock
        // Collapses to a zero-width point at the pill's centre when there
        // is no configured clock, rather than reserving clock-sized space
        // for something that isn't shown.
        visible: root.hasClock && !Config.appearance.ink
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        width: visible ? Math.min(implicitWidth, parent.width) : 0
        height: parent.height
        itemId: "Clock"
        monitor: root.monitor
        onControlCenterRequested: card => root.controlCenterRequested(card)
    }

    // Ink clock: Geist 15/600, one line, centred on the pill's own centre.
    Text {
        id: inkClock
        visible: Config.appearance.ink && root.hasClock
        // Ink: SharedClock (island/SharedElements.qml) draws the clock; this
        // stays laid out as the tag's measure, transparent.
        opacity: root.inkShared ? 0 : 1
        anchors.centerIn: parent
        text: ShellState.time
        color: Theme.t1
        font.family: Theme.fontUi
        font.pixelSize: 15
        font.weight: Font.DemiBold
        font.features: ({ "tnum": 1 })
    }

    // ---- ink shared-element tags (island/SharedElements.qml) -----------
    // Hover shows art 32px circle, title 13/600 and artist 12/500, and the
    // clock at 15/600. Each tag measures the copy above, which is invisible
    // under ink.
    SharePoint {
        id: shareArt
        objectName: "share:art"
        shareKind: "art"
        shareState: "hover"
        measure: hoverArt
        shareLive: root.hasMedia
    }
    SharePoint {
        id: shareTitle
        objectName: "share:title"
        shareKind: "title"
        shareState: "hover"
        measure: inkTextCol
        shareLive: root.hasMedia
        shareScale: 13 / 20
        shareSubScale: 12 / 13
    }
    SharePoint {
        id: shareClock
        objectName: "share:clock"
        shareKind: "clock"
        shareState: "hover"
        measure: inkClock
        shareLive: root.hasClock
        shareScale: 1
    }
    readonly property var shareItems: [shareArt, shareTitle, shareClock]

    // ---- media: art flush to the pill's own left corner -----------------
    Item {
        id: mediaBlock
        visible: root.hasMedia
        anchors.left: parent.left
        anchors.leftMargin: Config.appearance.ink ? 10 : root.inset
        anchors.top: parent.top
        anchors.topMargin: root.inset
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.inset
        // Ink: bound by the VISIBLE ink clock. hoverClock is hidden under
        // ink but still sits at the centre, so anchoring to it let the
        // title run underneath the clock.
        anchors.right: Config.appearance.ink ? inkClock.left : hoverClock.left
        anchors.rightMargin: Config.appearance.ink ? 16 : (root.hasMedia ? Theme.space2 : 0)
        clip: true

        // impasto card pages (DeskSettings.islandImpastoCards): the media
        // block opens the player card directly, reached without the
        // dashboard/control-centre detour.
        TapHandler {
            onTapped: root.controlCenterRequested("player")
        }

        RowLayout {
            anchors.fill: parent
            spacing: Theme.space2

            ClippingRectangle {
                id: hoverArt
                // Ink: a 32px art disc (showcase .art32), not full pill height.
                // Under ink, SharedArt draws it; this keeps the slot.
                opacity: root.inkShared ? 0 : 1
                Layout.preferredWidth: Config.appearance.ink ? 32 : mediaBlock.height
                Layout.preferredHeight: Config.appearance.ink ? 32 : mediaBlock.height
                Layout.alignment: Qt.AlignVCenter
                // Circular per the owner's Figma redesign (node 4:2).
                radius: width / 2
                color: Config.appearance.ink ? Theme.inkRaised : Theme.primaryContainer

                Image {
                    id: artworkImage
                    anchors.fill: parent
                    source: MediaService.artwork
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    visible: status === Image.Ready
                }
                Text {
                    anchors.centerIn: parent
                    visible: artworkImage.status !== Image.Ready
                    text: "󰎈"
                    color: Config.appearance.ink ? Theme.t2 : Theme.primaryContainerText
                    font.family: Config.appearance.monoFontFamily
                    // Theme.iconSmall already carries DisplayScale.primary
                    // and so does hoverIconScale now (core/Config.qml) --
                    // divide back out to avoid double-scaling.
                    font.pixelSize: Math.round(Theme.iconSmall
                        * (Config.island.hoverIconScale / DisplayScale.primary))
                }
            }

            ColumnLayout {
                id: inkTextCol
                Layout.fillWidth: true
                // Ink: width comes from the anchors (art .. clock - 16px).
                Layout.maximumWidth: Number.POSITIVE_INFINITY
                Layout.alignment: Qt.AlignVCenter
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space1

                    Eq {
                        active: MediaService.playing
                        visible: MediaService.playing && !Config.appearance.ink
                        // DisplayScale.primary: bare literal, found during
                        // the pill text/icon audit -- unlike every other
                        // island size, this one wasn't gated behind
                        // hoverIconScale/hoverTextScale at all.
                        maxH: Math.round(10 * DisplayScale.primary)
                        barColor: AdaptiveColor.activeFill
                    }
                    Text {
                        Layout.fillWidth: true
                        // Ink: SharedTitle draws the title and artist.
                        opacity: root.inkShared ? 0 : 1
                        text: MediaService.title
                        color: Config.appearance.ink ? Theme.t1 : AdaptiveColor.glassText
                        font.family: Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily
                        // Same double-scale note as above.
                        font.pixelSize: Config.appearance.ink ? 13 : Math.round(Theme.textSmall
                            * (Config.island.hoverTextScale / DisplayScale.primary))
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                }
                Text {
                    Layout.fillWidth: true
                    opacity: root.inkShared ? 0 : 1
                    text: MediaService.artist
                    color: Config.appearance.ink ? Theme.t2 : AdaptiveColor.glassTextDim
                    font.family: Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily
                    font.pixelSize: Config.appearance.ink ? 12 : Math.round(10
                        * Config.island.hoverTextScale)
                    font.weight: Config.appearance.ink ? Font.Medium : Font.Normal
                    elide: Text.ElideRight
                }
            }
        }
    }

    // ---- status: one rounded capsule in the right corner -----------------
    Rectangle {
        id: statusCapsule
        visible: root.hasCapsuleContent
        anchors.right: parent.right
        anchors.rightMargin: Config.appearance.ink ? 14 : root.inset
        anchors.top: parent.top
        anchors.topMargin: root.inset
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.inset
        implicitWidth: capsuleRow.implicitWidth + Theme.space3 * 2
        radius: height / 2
        // A faint wash on surfaceText (the Figma capsule is white at 6%
        // opacity) reads correctly in both light and dark themes, unlike a
        // literal white hex would.
        // Ink: no capsule fill, the status glyphs sit directly on the ink.
        color: Config.appearance.ink ? "transparent" : Qt.alpha(AdaptiveColor.glassText, 0.06)

        // Restores master's whole-capsule tap for the DEAD SPACE between
        // icons (the RowLayout's own spacing, and any margin around it) --
        // a tap there falls through to "overview" exactly like every
        // capsule tap used to. This does NOT double-fire alongside a
        // per-icon TapHandler below: QtQuick's pointer handlers resolve a
        // tap to whichever handler's OWN bounds it lands in, innermost
        // first, and a child TapHandler that takes the exclusive grab for
        // its (smaller) bounds is never also offered to this outer one for
        // the same point -- confirmed by this capsule's per-entry
        // TapHandlers being declared purely inside each entry's own
        // implicitWidth/Height (never anchors.fill: parent or a larger
        // area), so their hit region is strictly smaller than and
        // contained within this one.
        TapHandler {
            onTapped: root.controlCenterRequested("")
        }

        RowLayout {
            id: capsuleRow
            anchors.centerIn: parent
            spacing: Theme.space2

            Repeater {
                model: root.capsuleOrder
                delegate: Item {
                    id: capsuleEntry
                    required property string modelData
                    readonly property bool isBattery: modelData === "Battery"
                    // Glass redesign: Network renders the StatusOrb (Wi-Fi +
                    // Bluetooth in one), so a separate Bluetooth glyph is
                    // dropped whenever Network is in the capsule. Battery folds
                    // into the orb ring too.
                    // Ink: no orb (its green ring was the only colour in the
                    // chrome); each status is its own monochrome Lucide icon.
                    readonly property bool isOrb: modelData === "Network" && !Config.appearance.ink
                    readonly property string inkIcon: modelData === "Network"
                            ? (ConnectivityStatus.ethernet ? "ethernet-port" : (NetworkService.connected ? "wifi" : "wifi-off"))
                        : modelData === "Bluetooth" ? (ConnectivityStatus.btDevices > 0 ? "bluetooth-connected" : "bluetooth")
                        : modelData === "Audio" ? (AudioService.muted ? "volume-x" : "volume-2")
                        : modelData === "Dnd" ? (NotificationService.doNotDisturb ? "bell-off" : "bell")
                        : modelData === "KeepAwake" ? "coffee" : ""
                    visible: root.capsuleItemVisible(modelData)
                        && (Config.appearance.ink
                            ? (modelData !== "Battery" || BatteryService.available)
                            : (!(modelData === "Bluetooth" && root.capsuleOrder.indexOf("Network") >= 0)
                                && !(modelData === "Battery" && root.capsuleOrder.indexOf("Network") >= 0)))
                    implicitWidth: isBattery ? batteryBadge.implicitWidth
                        : isOrb ? capsuleOrb.width
                        : (Config.appearance.ink && inkIcon !== "") ? 18 : glyph.implicitWidth
                    implicitHeight: isBattery ? batteryBadge.implicitHeight
                        : isOrb ? capsuleOrb.height
                        : (Config.appearance.ink && inkIcon !== "") ? 18 : glyph.implicitHeight

                    Icon {
                        visible: Config.appearance.ink && !capsuleEntry.isBattery && capsuleEntry.inkIcon !== ""
                        anchors.centerIn: parent
                        name: capsuleEntry.inkIcon
                        size: 18
                        color: (capsuleEntry.modelData === "Network" && !NetworkService.connected && !ConnectivityStatus.ethernet) ? Theme.t3 : Theme.t1
                    }

                    StatusOrb {
                        id: capsuleOrb
                        visible: capsuleEntry.isOrb
                        anchors.centerIn: parent
                        width: Math.round(Theme.iconSmall * 1.55
                            * (Config.island.hoverIconScale / DisplayScale.primary))
                        height: width
                        wifiStrength: ConnectivityStatus.wifiStrength
                        ethernet: ConnectivityStatus.ethernet
                        btEnabled: ConnectivityStatus.btEnabled
                        btSignal: ConnectivityStatus.btSignal
                        btDevices: ConnectivityStatus.btDevices
                        batteryLevel: BatteryService.available ? BatteryService.percentage : -1
                        charging: BatteryService.charging
                    }

                    Text {
                        id: glyph
                        visible: !capsuleEntry.isBattery && !capsuleEntry.isOrb
                            && !(Config.appearance.ink && capsuleEntry.inkIcon !== "")
                        text: modelData === "Network" ? NetworkService.icon
                            : modelData === "Bluetooth" ? BluetoothService.icon
                            : modelData === "Audio"
                                ? (AudioService.muted ? "󰝟" : "󰕾")
                            : modelData === "Dnd"
                                ? (NotificationService.doNotDisturb ? "󰂛" : "󰂚")
                            : modelData === "KeepAwake" ? "󰅶"
                            : ""
                        color: Config.appearance.ink
                            ? ((capsuleEntry.modelData === "Network" && !NetworkService.connected) ? Theme.t3 : Theme.t1)
                            : modelData === "Network"
                                ? (NetworkService.connected ? AdaptiveColor.activeFill
                                    : AdaptiveColor.glassTextDim)
                            : modelData === "Bluetooth" ? AdaptiveColor.activeFill
                            : modelData === "Audio"
                                ? (AudioService.muted ? Theme.error : AdaptiveColor.activeFill)
                            : modelData === "Dnd"
                                ? (NotificationService.doNotDisturb
                                    ? Theme.tertiary : AdaptiveColor.glassText)
                            : modelData === "KeepAwake"
                                ? (IdleService.inhibited ? Theme.error
                                    : AdaptiveColor.glassText)
                            : AdaptiveColor.glassText
                        font.family: Config.appearance.monoFontFamily
                        // Theme.iconSmall already carries DisplayScale.primary
                        // and so does hoverIconScale now -- divide back out.
                        font.pixelSize: Math.round(Theme.iconSmall
                            * (Config.island.hoverIconScale / DisplayScale.primary))
                    }

                    // Battery reads as a filled badge in the owner's Figma
                    // (node 4:2), not a plain glyph -- Theme.success stands
                    // in for the mockup's charge-green, and low-charge still
                    // flags red the same way the rest of the shell does.
                    Rectangle {
                        id: batteryBadge
                        visible: capsuleEntry.isBattery
                        readonly property bool low: BatteryService.percentageInt <= 15
                            && BatteryService.onBattery
                        implicitWidth: batteryText.implicitWidth + Theme.space2 * 2
                        implicitHeight: Math.round(16 * Config.island.hoverIconScale)
                        radius: Theme.u(0.14)
                        color: low ? Theme.error : Theme.success

                        Text {
                            id: batteryText
                            anchors.centerIn: parent
                            text: BatteryService.percentageInt
                            color: Theme.foregroundFor(batteryBadge.color)
                            font.family: Config.appearance.monoFontFamily
                            font.weight: Font.Medium
                            font.pixelSize: Math.round(10
                                * Config.island.hoverIconScale)
                        }
                    }

                    // impasto card pages (DeskSettings.islandImpastoCards):
                    // this entry's own footprint (implicitWidth/Height
                    // above are already sized to just its glyph/badge) IS
                    // its hit area, and entries sit side by side in
                    // capsuleRow's RowLayout -- so exactly one entry's
                    // TapHandler can ever be under the pointer, never two
                    // overlapping. Wifi/bluetooth/battery/audio(volume)
                    // open their own card; everything else (Dnd/KeepAwake/
                    // Workspaces, which have no card) restores master's
                    // original whole-capsule behaviour of opening the
                    // dashboard -- root.controlCenterRequested("") resolves
                    // to "overview" in island/Island.qml's handler exactly
                    // the way master's plain root.controlCenterRequested()
                    // did.
                    TapHandler {
                        cursorShape: Qt.PointingHandCursor
                        onTapped: root.controlCenterRequested(
                            root.cardForCapsuleItem(capsuleEntry.modelData))
                    }
                }
            }
        }
    }
}
