// Ported from impasto's bar/island/GamesPanel.qml
// (github.com/andreumassanet/impasto, GPL-3.0, Andreu Massanet), verbatim
// except: Theme -> Desk.DeskTheme; GamesService -> DeskGamesService
// (desktop/services/DeskGamesService.qml, already shipped -- its
// catalogue/entry/tintOf/panelSize/open/leave/played/bestOf/record/
// stripGap/stripHeight/shelfWidth/shelfHeight already match impasto's own
// GamesService one-for-one); Carousel/CarouselTile/PillButton imported from
// dashboard/components and desktop/components (Carousel/CarouselTile
// ported this same phase, PillButton already shipped); ./games ->
// dashboard/games (the 11 games + GameBoard.qml, ported this same phase,
// verbatim except the same Theme/GamesService renames).
//
// An earlier round of this port replaced this whole file with a
// score-catalogue-only stub (no real board, "Play" a no-op) because the
// individual games hadn't been ported yet. They have been now -- every
// game file only ever imported QtQuick + impasto's theme (no
// GamesService/other-service dependency inside a game itself), so the
// port really is the rename above and nothing else. This file replaces
// that stub with the real arcade: the shelf carousel and the running-game
// frame (score/best strip, game-over overlay, R/Enter/Space to restart).

import QtQuick
import QtQuick.Layouts

import "../desktop/services" as Desk
import "../desktop/components" as DeskComponents
import "components" as DashComponents
import "./games" as Games
import "../components"

FocusScope {
    id: root

    signal closed()

    readonly property string playing: Desk.DeskGamesService.playing
    readonly property var game: Desk.DeskGamesService.entry(root.playing)

    // Focus on open, or the arrows go to whatever had the keyboard before.
    Component.onCompleted: root.forceActiveFocus()

    // Closing the panel leaves the game, so it reopens on the shelf.
    Component.onDestruction: Desk.DeskGamesService.leave()

    Keys.onEscapePressed: event => {
        if (root.playing === "") {
            event.accepted = false
            return
        }
        Desk.DeskGamesService.leave()
    }

    Loader {
        anchors.fill: parent
        focus: true
        sourceComponent: root.playing === "" ? shelf : frame
    }

    // ── SHELF ───────────────────────────────────────────────────────────────

    Component {
        id: shelf

        Item {
            id: page

            readonly property var chosen: Desk.DeskGamesService.catalogue[strip.current] ?? null

            // The game last opened. An initial value for `current` rather than
            // a later call, so the shelf opens there instead of sliding from
            // the first tile.
            readonly property int opening: Math.max(0, Desk.DeskGamesService.catalogue.findIndex(
                item => item.id === Desk.DeskGamesService.lastOpened))

            // Explicit: `focus: true` down the chain does not reach an item
            // inside a Loader.
            Component.onCompleted: page.forceActiveFocus()

            function play(): void {
                if (page.chosen)
                    Desk.DeskGamesService.open(page.chosen.id)
            }

            Keys.onLeftPressed: strip.step(-1)
            Keys.onRightPressed: strip.step(1)
            Keys.onReturnPressed: page.play()
            Keys.onEnterPressed: page.play()
            Keys.onSpacePressed: page.play()
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Home)
                    strip.goTo(0)
                else if (event.key === Qt.Key_End)
                    strip.goTo(strip.count - 1)
                else
                    return
                event.accepted = true
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: Desk.DeskGamesService.stripGap

                DashComponents.Carousel {
                    id: strip

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    current: page.opening
                    model: Desk.DeskGamesService.catalogue
                    onActivated: page.play()

                    delegate: DashComponents.CarouselTile {
                        id: card

                        readonly property color tint: Desk.DeskGamesService.tintOf(card.modelData.id)

                        Squircle {
                            anchors.fill: parent
                            radius: Desk.DeskTheme.radiusMedium
                            color: card.hovered ? Desk.DeskTheme.islandSurfaceHover : Desk.DeskTheme.islandSurface
                            // Ringed in the game's own tint, which its board
                            // also uses.
                            borderColor: card.centred ? card.tint : Desk.DeskTheme.islandBorder
                            borderWidth: card.centred ? 2 : 1

                            Behavior on color { ColorAnimation { duration: Desk.DeskTheme.durationFast } }
                            Behavior on borderColor { ColorAnimation { duration: Desk.DeskTheme.durationFast } }

                            Column {
                                anchors.centerIn: parent
                                spacing: 8

                                // The glyph on a tile of its own colour, like
                                // a launcher icon: the tint at a fifth, the
                                // glyph at full.
                                Squircle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 44
                                    height: 44
                                    radius: 11
                                    color: Qt.rgba(card.tint.r, card.tint.g, card.tint.b, 0.2)

                                    Text {
                                        anchors.centerIn: parent
                                        text: card.modelData.icon
                                        font.family: Desk.DeskTheme.fontMono
                                        font.pixelSize: 22
                                        color: card.tint
                                    }
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: card.modelData.name
                                    font.family: Desk.DeskTheme.fontFamily
                                    font.pixelSize: Desk.DeskTheme.fontSizeSmall
                                    font.weight: card.centred ? Font.DemiBold : Font.Normal
                                    color: card.centred ? Desk.DeskTheme.text : Desk.DeskTheme.textMuted
                                }
                            }
                        }
                    }
                }

                // The middle game's best, and where in the shelf it is.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Desk.DeskGamesService.stripGap

                    Text {
                        Layout.fillWidth: true
                        text: !page.chosen ? ""
                            : Desk.DeskGamesService.played(page.chosen.id)
                                ? `Best ${Desk.DeskGamesService.bestOf(page.chosen.id)}`
                                : "Not played yet"
                        elide: Text.ElideRight
                        font.family: Desk.DeskTheme.fontMono
                        font.pixelSize: Desk.DeskTheme.fontSizeSmall
                        color: Desk.DeskTheme.textMuted
                    }

                    Text {
                        text: strip.count === 0 ? "" : `${strip.current + 1}/${strip.count}`
                        font.family: Desk.DeskTheme.fontFamily
                        font.pixelSize: Desk.DeskTheme.fontSizeSmall
                        color: Desk.DeskTheme.textMuted
                    }
                }
            }
        }
    }

    // ── FRAME ───────────────────────────────────────────────────────────────

    Component {
        id: frame

        ColumnLayout {
            id: round

            // Whether the round that just ended beat the best. Set from the
            // record, and cleared on restart.
            property bool beaten: false

            readonly property var played: board.game
            readonly property bool over: round.played ? round.played.over : false
            readonly property int score: round.played ? round.played.score : 0
            readonly property bool byMoves: root.game ? root.game.lower : false

            spacing: Desk.DeskGamesService.stripGap

            function again(): void {
                round.beaten = false
                if (round.played)
                    round.played.restart()
            }

            // R restarts at any time. Enter and Space do too once the round
            // is over; while it runs they belong to the game. No game uses R.
            Keys.onPressed: event => {
                const again = event.key === Qt.Key_R
                    || (round.over && (event.key === Qt.Key_Return
                        || event.key === Qt.Key_Enter || event.key === Qt.Key_Space))
                if (!again)
                    return
                round.again()
                event.accepted = true
            }

            Connections {
                target: round.played

                function onFinished(score: int): void {
                    round.beaten = Desk.DeskGamesService.record(root.playing, score)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: Desk.DeskGamesService.stripHeight
                spacing: 10

                // Just the score and the best: no name, no key hints, and no
                // buttons for what a key already does.
                Item { Layout.fillWidth: true }

                Text {
                    text: `${round.byMoves ? "Moves" : "Score"} ${round.score}`
                    font.family: Desk.DeskTheme.fontMono
                    font.pixelSize: Desk.DeskTheme.fontSizeSmall
                    font.weight: Font.DemiBold
                    color: Desk.DeskTheme.text
                }

                Text {
                    visible: Desk.DeskGamesService.played(root.playing)
                    text: `Best ${Desk.DeskGamesService.bestOf(root.playing)}`
                    font.family: Desk.DeskTheme.fontMono
                    font.pixelSize: Desk.DeskTheme.fontSizeSmall
                    color: Desk.DeskTheme.textMuted
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Games.GameBoard {
                    id: board

                    anchors.fill: parent
                    gameId: root.playing
                    tint: Desk.DeskGamesService.tintOf(root.playing)
                }

                // Over the board once the round ends; the board stays visible
                // beneath it.
                Squircle {
                    anchors.fill: parent
                    visible: opacity > 0
                    opacity: round.over ? 1 : 0
                    radius: Desk.DeskTheme.radiusMedium
                    color: Desk.DeskTheme.scrim

                    Behavior on opacity {
                        NumberAnimation { duration: Desk.DeskTheme.durationMedium; easing.type: Desk.DeskTheme.easing }
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 10

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: round.byMoves ? "Solved" : "Game over"
                            font.family: Desk.DeskTheme.fontFamily
                            font.pixelSize: Desk.DeskTheme.fontSizeLarge
                            font.weight: Font.DemiBold
                            color: Desk.DeskTheme.scrimText
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: round.beaten
                                ? `New best · ${round.score}`
                                : `${round.byMoves ? "Moves" : "Score"} ${round.score}`
                            font.family: Desk.DeskTheme.fontMono
                            font.pixelSize: Desk.DeskTheme.fontSizeMedium
                            color: round.beaten ? Desk.DeskTheme.indicatorWarn : Desk.DeskTheme.scrimText
                        }

                        DeskComponents.PillButton {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Play again"
                            active: true
                            onClicked: round.again()
                        }
                    }

                    // A click on the wash is the same as the button.
                    MouseArea {
                        anchors.fill: parent
                        z: -1
                        onClicked: round.again()
                    }
                }
            }
        }
    }
}
