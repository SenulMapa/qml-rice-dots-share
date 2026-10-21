// Ported from impasto's bar/island/games/Lights.qml
// (github.com/andreumassanet/impasto, GPL-3.0, Andreu Massanet), verbatim
// except: Theme -> Desk.DeskTheme.

import QtQuick

import "../../desktop/services" as Desk
import "../../components"

// Lights Out: pressing a light flips it and its four neighbours; the round
// ends when all 25 are off. The score is the press count (lower is better) and
// `finished` fires only on a dark board.
//
// Each start applies six to ten distinct presses to a dark board, so it is
// always solvable in a few moves.
FocusScope {
    id: root

    // ── CONTRACT ────────────────────────────────────────────────────────────

    property int score: 0
    property bool over: false
    property color tint: Desk.DeskTheme.accent

    signal finished(int score)

    function restart(): void {
        let board = []
        // Distinct, since a repeated press undoes itself.
        do {
            board = Array.from({ length: root.count }, () => false)
            const presses = 6 + Math.floor(Math.random() * 5)
            const pressed = new Set()
            while (pressed.size < presses)
                pressed.add(Math.floor(Math.random() * root.count))
            for (const index of pressed)
                board = root.flipped(board, index)
        } while (board.every(lit => !lit))
        root.lights = board
        root.selected = Math.floor(root.count / 2)
        root.score = 0
        root.over = false
    }

    // ── BOARD ───────────────────────────────────────────────────────────────

    readonly property int size: 5
    readonly property int count: root.size * root.size
    readonly property int gap: 12
    readonly property int pad: 26
    readonly property int cell: Math.max(1, Math.floor(
        (Math.min(root.width, root.height) - 2 * root.pad - (root.size - 1) * root.gap)
        / root.size))
    readonly property int stride: root.cell + root.gap
    readonly property int span: root.size * root.cell + (root.size - 1) * root.gap

    // Row-major, true where a light is on.
    property var lights: []
    // Keyboard cursor. Arrows move it; a click moves it too.
    property int selected: 0

    focus: true

    Component.onCompleted: root.restart()

    // A copy with the cross at `index` flipped; edge cells have fewer
    // neighbours.
    function flipped(board: var, index: int): var {
        const next = board.slice()
        const column = index % root.size
        const row = Math.floor(index / root.size)
        const flip = (x, y) => {
            if (x >= 0 && x < root.size && y >= 0 && y < root.size)
                next[y * root.size + x] = !next[y * root.size + x]
        }
        for (const [dx, dy] of [[0, 0], [-1, 0], [1, 0], [0, -1], [0, 1]])
            flip(column + dx, row + dy)
        return next
    }

    function press(index: int): void {
        if (root.over)
            return
        root.selected = index
        root.lights = root.flipped(root.lights, index)
        root.score += 1
        if (root.lights.every(lit => !lit)) {
            root.over = true
            root.finished(root.score)
        }
    }

    Keys.onPressed: event => {
        let column = root.selected % root.size
        let row = Math.floor(root.selected / root.size)
        switch (event.key) {
        case Qt.Key_Up:    row -= 1;    break
        case Qt.Key_Down:  row += 1;    break
        case Qt.Key_Left:  column -= 1; break
        case Qt.Key_Right: column += 1; break
        case Qt.Key_Space: root.press(root.selected); break
        default: return
        }
        // Clamped at the edges rather than wrapping.
        root.selected = Math.max(0, Math.min(root.size - 1, row)) * root.size
            + Math.max(0, Math.min(root.size - 1, column))
        event.accepted = true
    }

    Squircle {
        id: ground

        anchors.centerIn: parent
        width: root.span + 2 * root.pad
        height: width
        radius: Desk.DeskTheme.radiusMedium
        color: Desk.DeskTheme.islandSurface
        borderColor: Desk.DeskTheme.islandBorder
        borderWidth: 1

        // The model is the count, not the array: given the array, the Repeater
        // would rebuild every light on each press, and a Behavior never fires
        // on a property's first evaluation.
        Repeater {
            model: root.count

            delegate: Item {
                id: light

                required property int index

                readonly property bool lit: root.lights[light.index] === true

                x: root.pad + (light.index % root.size) * root.stride
                y: root.pad + Math.floor(light.index / root.size) * root.stride
                width: root.cell
                height: root.cell

                // Glow: a wider tinted disc behind the light, faded by opacity.
                Rectangle {
                    anchors.centerIn: parent
                    width: root.cell + root.gap
                    height: width
                    radius: width / 2
                    color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, 0.22)
                    opacity: light.lit ? 1 : 0

                    Behavior on opacity { NumberAnimation { duration: Desk.DeskTheme.durationFast } }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: light.lit ? root.tint : Desk.DeskTheme.islandSurfaceHover
                    border.color: light.lit ? root.tint : Desk.DeskTheme.islandBorder
                    border.width: 1

                    Behavior on color        { ColorAnimation { duration: Desk.DeskTheme.durationFast } }
                    Behavior on border.color { ColorAnimation { duration: Desk.DeskTheme.durationFast } }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.press(light.index)
                }
            }
        }

        // The keyboard ring, declared after the lights so it draws over them.
        // One axis moves per arrow, so the two Behaviors never overlap.
        Rectangle {
            id: ring

            x: root.pad + (root.selected % root.size) * root.stride - root.gap / 2
            y: root.pad + Math.floor(root.selected / root.size) * root.stride - root.gap / 2
            width: root.cell + root.gap
            height: width
            radius: width / 2
            color: "transparent"
            border.color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, 0.45)
            border.width: 2

            Behavior on x {
                NumberAnimation { duration: Desk.DeskTheme.durationFast; easing.type: Desk.DeskTheme.easing }
            }
            Behavior on y {
                NumberAnimation { duration: Desk.DeskTheme.durationFast; easing.type: Desk.DeskTheme.easing }
            }
        }
    }
}
