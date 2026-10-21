pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects

/**
 * DiffusionText -- per-letter diffusion blur, ported from the Dollars
 * landing loader's headline animation (/tmp/dollars-loader-spec.md "Letter
 * diffusion blur"): blur 15px->0, opacity 0->1, translateY 7px->0, 620ms per
 * letter, 34ms stagger, cubic-bezier(.22,1,.36,1), left-to-right order.
 *
 * `direction: "out"` plays the exact reverse for the unlock sequence's step
 * (a): opacity 1->0, blur back up to 15px, translateY back to 7px, staggered
 * right-to-left instead of left-to-right -- the mirror image of the
 * entrance, not just a fade.
 *
 * Each character gets its own Text plus a MultiEffect blur layer, but that
 * layer is only enabled WHILE that specific character is actually mid
 * animation (`cell.running`). Once a letter settles -- fully shown after
 * "in", fully hidden after "out" -- its layer switches off, so the quote
 * sitting at rest isn't paying for 40-odd offscreen blur passes forever.
 */
Item {
    id: root

    required property string text
    property color textColor: "white"
    property int pixelSize: 22
    property string fontFamily: ""
    property bool animating: false
    property string direction: "in" // "in" or "out"

    readonly property int letterRun: 620
    readonly property int letterStep: 34
    readonly property var bezier: [0.22, 1, 0.36, 1, 1, 1]

    // Fires once every letter has finished its own animation for the
    // current direction.
    signal animationFinished()

    readonly property var chars: root.text.split("")
    property int _settled: 0

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight
    width: implicitWidth
    height: implicitHeight

    onAnimatingChanged: {
        if (!root.animating) return
        root._settled = 0
        for (let i = 0; i < repeater.count; i++) {
            const cell = repeater.itemAt(i)
            if (cell) cell.play()
        }
    }

    function _onCellSettled(): void {
        root._settled += 1
        if (root._settled === root.chars.length) {
            root.animating = false
            root.animationFinished()
        }
    }

    Row {
        id: row
        anchors.centerIn: parent

        Repeater {
            id: repeater
            model: root.chars

            delegate: Item {
                id: cell
                required property string modelData
                required property int index

                // Left-to-right for "in", right-to-left for "out".
                readonly property int order: root.direction === "in"
                    ? cell.index : (root.chars.length - 1 - cell.index)
                // 1 = fully revealed (settled "in" look), 0 = fully hidden
                // (settled pre-entrance / settled "out" look). Both `blur`
                // and `translateY` below are derived from this single
                // driven value so all three properties stay in lockstep on
                // the same eased curve, exactly like the source CSS
                // animation keyframing them together.
                property real progress: root.direction === "in" ? 0 : 1
                property bool running: false

                width: letterText.implicitWidth
                height: letterText.implicitHeight

                function play(): void {
                    cell.running = true
                    delay.interval = cell.order * root.letterStep
                    delay.restart()
                }

                Timer {
                    id: delay
                    repeat: false
                    onTriggered: anim.restart()
                }
                NumberAnimation {
                    id: anim
                    target: cell
                    property: "progress"
                    to: root.direction === "in" ? 1 : 0
                    duration: root.letterRun
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: root.bezier
                    onFinished: {
                        cell.running = false
                        root._onCellSettled()
                    }
                }

                layer.enabled: cell.running
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blurMax: 15
                    blur: 1 - cell.progress
                }

                transform: Translate {
                    y: (1 - cell.progress) * 7
                }

                Text {
                    id: letterText
                    // Non-breaking space so a real space still reserves its
                    // width instead of collapsing at the Row's edge.
                    text: cell.modelData === " " ? " " : cell.modelData
                    color: root.textColor
                    font.pixelSize: root.pixelSize
                    font.family: root.fontFamily
                    opacity: cell.progress
                }
            }
        }
    }
}
