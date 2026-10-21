// Ported from impasto's bar/island/controls/BlockFace.qml
// (github.com/andreumassanet/impasto, GPL-3.0, Andreu Massanet).
//
// Registry of control centre blocks: an id in, a card out. The card is told
// its cell count so blocks with several faces can pick one. A new block
// needs a row in DashBlocksService.catalogue and one here.
//
// Adaptation:
//   - ControlsService -> DashServices.DashBlocksService; Theme -> Desk.DeskTheme.
//   - Every card is one already shipped by the earlier dashboard-port phase
//     (dashboard/controls/*.qml) rather than a re-port of impasto's own --
//     see each card's own header for its adaptation notes. `volume` and
//     `brightness` stay upstream's own inline SliderRow sliders, bound to
//     this shell's DeskAudioService/DeskBrightnessService instead of
//     impasto's AudioService/BrightnessService. `notes` stays upstream's
//     own inline Sticky note, bound to this shell's NotesService.
//   - Upstream's "impasto" block (its own wordmark/palette-board signature
//     card) is dropped -- see DashBlocksService.qml's header.
//   - `appearanceBlock` drops upstream's `onRequested: root.panelRequested
//     ("appearance")` wire: this shell's AppearanceCard.qml is its own
//     documented "Simplified port" with the picker inline (no palette list
//     to drill into), so it has no `requested` signal to wire -- not a
//     dropped interaction, there is nothing left to open.

import QtQuick

import "../../desktop/services" as Desk
import "../../desktop/components" as DeskComponents
import "../services" as DashServices

Item {
    id: root

    property string blockId: ""
    property string size: "2x2"

    // The grid row this face draws; only the toggles block needs it.
    property string blockKey: ""

    // Nothing is built for a block that is not on the grid.
    property bool active: true

    signal panelRequested(string panel)
    signal dismissed()

    readonly property var shape: DashServices.DashBlocksService.parse(root.size)

    readonly property var components: ({
        toggles: togglesBlock,
        volume: volumeBlock,
        brightness: brightnessBlock,
        appearance: appearanceBlock,
        media: mediaBlock,
        weather: weatherBlock,
        calendar: calendarBlock,
        notifications: notificationsBlock,
        pet: petBlock,
        clock: clockBlock,
        games: gamesBlock,
        notes: notesBlock,
        tasks: tasksBlock
    })

    Loader {
        anchors.fill: parent
        active: root.active
        sourceComponent: root.components[root.blockId] ?? null
    }

    Component {
        id: togglesBlock
        TogglesBlock {
            blockKey: root.blockKey
            cols: root.shape.cols
            rows: root.shape.rows
            onPanelRequested: panel => root.panelRequested(panel)
            onDismissed: root.dismissed()
        }
    }

    // Sliders are shorter than a cell and centred in it.
    Component {
        id: volumeBlock
        Item {
            DeskComponents.SliderRow {
                anchors.centerIn: parent
                width: parent.width
                height: Math.min(parent.height, 48)
                icon: Desk.DeskAudioService.icon
                value: Desk.DeskAudioService.volume
                available: Desk.DeskAudioService.available
                dimmed: Desk.DeskAudioService.muted
                onMoved: value => Desk.DeskAudioService.setVolume(value)
                onIconClicked: Desk.DeskAudioService.toggleMute()
            }
        }
    }

    Component {
        id: brightnessBlock
        Item {
            DeskComponents.SliderRow {
                anchors.centerIn: parent
                width: parent.width
                height: Math.min(parent.height, 48)
                icon: Desk.DeskBrightnessService.icon
                value: Desk.DeskBrightnessService.percent
                from: 1
                available: Desk.DeskBrightnessService.available
                onMoved: value => Desk.DeskBrightnessService.setBrightness(value)
            }
        }
    }

    Component {
        id: appearanceBlock
        AppearanceCard { cols: root.shape.cols; rows: root.shape.rows }
    }

    Component {
        id: mediaBlock
        MediaCard { cols: root.shape.cols; rows: root.shape.rows }
    }

    Component {
        id: weatherBlock
        WeatherCard {
            cols: root.shape.cols
            rows: root.shape.rows
        }
    }

    Component {
        id: calendarBlock
        CalendarCard { onPanelRequested: panel => root.panelRequested(panel) }
    }

    Component {
        id: notificationsBlock
        NotificationList { cols: root.shape.cols; rows: root.shape.rows }
    }

    Component {
        id: petBlock
        PetBlock {
            rows: root.shape.rows
            onPanelRequested: panel => root.panelRequested(panel)
        }
    }

    Component {
        id: gamesBlock
        GamesBlock {
            rows: root.shape.rows
            onPanelRequested: panel => root.panelRequested(panel)
        }
    }

    Component {
        id: clockBlock
        ClockBlock {
            cols: root.shape.cols
            rows: root.shape.rows
        }
    }

    // A note with no card around it. Clicking opens it for editing.
    Component {
        id: notesBlock
        Item {
            readonly property var note: Desk.NotesService.noteFor(null)

            DeskComponents.Sticky {
                anchors.fill: parent
                note: parent.note
                placeholder: "No notes yet"
                padding: root.shape.cols === 1 ? 12 : 14
                titleSize: root.shape.rows >= 4 ? Desk.DeskTheme.fontSizeRegular : Desk.DeskTheme.fontSizeSmall
                bodySize: root.shape.rows >= 4 ? 20 : 16
            }

            HoverHandler { cursorShape: Qt.PointingHandCursor }

            TapHandler {
                gesturePolicy: TapHandler.ReleaseWithinBounds
                onTapped: {
                    Desk.NotesService.open(parent.note ? parent.note.key : "")
                    root.panelRequested("notes")
                }
            }
        }
    }

    Component {
        id: tasksBlock
        TasksBlock {
            cols: root.shape.cols
            rows: root.shape.rows
            onPanelRequested: panel => root.panelRequested(panel)
        }
    }
}
