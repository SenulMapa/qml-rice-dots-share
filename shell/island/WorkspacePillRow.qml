import QtQuick
import Quickshell
import "../core"
import "../components"
import "../services"

/**
 * WorkspacePillRow -- the resting pill's workspace-switch presentation
 * (island/IslandRestItem.qml's clockComponent swaps to this while
 * IslandController.workspaceSwitchActive is true). Shows workspaces
 * 1..maxWorkspaces: a number for an empty workspace, the focused/most-recent
 * client's app icon for an occupied one. A components/Bead travels from the
 * previously-active slot to the newly-active one, arcing above the row.
 *
 * MOTION: the bead is fed a single target point (slotCenterX(activeId), a
 * fixed lift above the row); its own spring/arc/retarget logic (see
 * components/Bead.qml) supplies the travelling-dot feel that used to live
 * here directly -- a horizontal-only travel vector arcs vertically for
 * free, since the bead's perpendicular bezier offset is normal to whatever
 * direction it's travelling. Only visible while actually travelling
 * (bead.moving), matching the original transient arc-dot behaviour.
 */
Item {
    id: root

    property int maxWorkspaces: 5
    property int previousWorkspaceId: 1
    // The pill height this row is actually rendering inside -- every slot/
    // gap/pad/glyph ratio below scales off THIS, not the global Theme
    // unit, so the row's rhythm tracks whatever height the resting pill
    // really is (core/BlobLayout.qml's kSlot/kGap/kPad/kIcon/kText).
    property real pillHeight: Config.island.dormantHeight
    readonly property real slotSize: root.pillHeight * BlobLayout.kSlot
    readonly property real slotSpacing: root.pillHeight * BlobLayout.kGap
    readonly property real edgePad: root.pillHeight * BlobLayout.kPad

    readonly property var indicatorIds: {
        const ids = []
        for (let i = 1; i <= Math.max(1, root.maxWorkspaces); ++i)
            ids.push(i)
        return ids
    }

    implicitWidth: BlobLayout.rowWidth(root.indicatorIds.length, root.pillHeight)
    implicitHeight: root.slotSize

    /** Index-based slot centre, in this Item's own local x. Pure function --
     *  shared by the real Row's layout AND the dot's target math below, so
     *  the two can never disagree about where a slot actually is. */
    function slotCenterX(workspaceId): real {
        const index = root.indicatorIds.indexOf(workspaceId)
        const clampedIndex = index === -1 ? 0 : index
        return clampedIndex * (root.slotSize + root.slotSpacing) + root.slotSize / 2
    }

    /** Most recent/focused client on a workspace, resolved to an icon name
     *  via Quickshell's desktop-entry heuristics (same lookup family the
     *  launcher's own theme icons use -- see launcher/PaletteResult.qml). */
    function iconForWorkspace(workspaceId): string {
        const workspace = HyprlandService.workspaceById(workspaceId)
        const clients = workspace?.toplevels?.values || []
        if (clients.length === 0)
            return ""
        const focused = HyprlandService.focusedToplevel
        const client = (focused && clients.indexOf(focused) !== -1)
            ? focused : clients[clients.length - 1]
        const appId = client?.lastIpcObject?.class
            || client?.lastIpcObject?.initialClass
            || client?.wayland?.appId || ""
        if (!appId)
            return ""
        const entry = typeof DesktopEntries !== "undefined"
            ? DesktopEntries.heuristicLookup(appId) : null
        return entry?.icon || ""
    }

    Row {
        anchors.centerIn: parent
        spacing: root.slotSpacing

        Repeater {
            model: root.indicatorIds
            delegate: Item {
                id: slot
                required property int modelData
                width: root.slotSize
                height: root.slotSize
                readonly property var workspace: HyprlandService.workspaceById(modelData)
                readonly property bool occupied:
                    HyprlandService.workspaceWindowCount(workspace) > 0
                readonly property bool current:
                    HyprlandService.activeWorkspaceId === modelData
                readonly property string iconName:
                    occupied ? root.iconForWorkspace(modelData) : ""
                readonly property bool showsIcon: iconName.length > 0

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: AdaptiveColor.activeFill
                    opacity: slot.current ? 0.16 : 0
                }

                Image {
                    visible: slot.showsIcon
                    anchors.centerIn: parent
                    // Same ratio token (kIcon) an icon slot ALWAYS uses,
                    // regardless of slot size -- so an icon and a bare
                    // number (kText below) read as the same visual weight
                    // instead of the icon being sized off its own parent
                    // (70% of the slot) while the number was a flat,
                    // unrelated pixel size.
                    width: root.pillHeight * BlobLayout.kIcon
                    height: width
                    sourceSize.width: width
                    sourceSize.height: height
                    source: slot.showsIcon ? Quickshell.iconPath(slot.iconName, true) : ""
                }

                Text {
                    visible: !slot.showsIcon
                    anchors.centerIn: parent
                    text: String(slot.modelData)
                    color: slot.current ? AdaptiveColor.activeFill : Theme.tertiary
                    font.family: Config.appearance.monoFontFamily
                    // root.pillHeight is already physical px (Config.island.
                    // dormantHeight or window.bodyH.value, both DisplayScale.
                    // primary-scaled) and restTextScale now ALSO carries
                    // DisplayScale.primary (core/Config.qml) -- divide it back
                    // out here so this doesn't double-scale; the user's own
                    // restTextScale percentage still applies.
                    font.pixelSize: Math.round(
                        root.pillHeight * BlobLayout.kText
                            * (Config.island.restTextScale / DisplayScale.primary))
                    font.features: ({ "tnum": 1 })
                }
            }
        }
    }

    // ---- the travelling bead ---------------------------------------------
    property int lastSeenWorkspaceId: root.previousWorkspaceId
    readonly property real beadLiftY: -root.slotSize / 2 - Theme.u(0.08)

    Connections {
        target: HyprlandService
        function onContextChanged(): void {
            const id = HyprlandService.activeWorkspaceId
            if (id > 0 && id !== root.lastSeenWorkspaceId)
                root.lastSeenWorkspaceId = id
        }
    }

    Bead {
        id: travelBead
        visible: moving
        form: "dot"
        dotSize: Theme.u(0.12)
        target: Qt.point(root.slotCenterX(root.lastSeenWorkspaceId), root.beadLiftY)
    }
}
