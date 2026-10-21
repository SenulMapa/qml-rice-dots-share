pragma ComponentBehavior: Bound
import QtQuick

/**
 * Steppers -- breaks a full-bleed fill into 6 vertical column pairs (a top
 * half and a bottom half each) that peel away vertically, revealing
 * whatever sits behind this Item. Timing ported from the Dollars landing
 * loader's stepper curtains (/tmp/dollars-loader-spec.md "Stepper
 * animation"): 6 columns, 920ms travel per column, 68ms stagger left to
 * right, cubic-bezier(.76,0,.24,1). Direction is the mirror of the loader's
 * (which CLOSES over content): here the fill is LEAVING, so the top half
 * travels up and the bottom half travels down, off past the container's own
 * edge, instead of the loader's curtains closing inward.
 */
Item {
    id: root

    property color fillColor: "black"
    readonly property int columnCount: 6
    readonly property int stepRun: 920
    readonly property int stepStagger: 68
    readonly property var bezier: [0.76, 0, 0.24, 1, 1, 1]

    // Fires once every column has finished its travel.
    signal breakFinished()

    property int _settled: 0

    function play(): void {
        root._settled = 0
        for (let i = 0; i < repeater.count; i++) {
            const col = repeater.itemAt(i)
            if (col) col.play()
        }
    }

    // Snaps every column back to its closed (fully covering) rest position
    // with no animation -- used to reset the preview/test fixture between
    // runs, never called mid-flight in the real sequence.
    function reset(): void {
        root._settled = 0
        for (let i = 0; i < repeater.count; i++) {
            const col = repeater.itemAt(i)
            if (col) col.resetInstant()
        }
    }

    function _onColumnSettled(): void {
        root._settled += 1
        if (root._settled === root.columnCount)
            root.breakFinished()
    }

    Row {
        anchors.fill: parent
        spacing: 0

        Repeater {
            id: repeater
            model: root.columnCount

            delegate: Item {
                id: column
                required property int index
                width: root.width / root.columnCount
                height: root.height

                function play(): void {
                    delay.interval = column.index * root.stepStagger
                    delay.restart()
                }
                function resetInstant(): void {
                    delay.stop()
                    topAnim.stop()
                    bottomAnim.stop()
                    top.y = 0
                    bottom.y = top.height
                }

                Rectangle {
                    id: top
                    color: root.fillColor
                    width: parent.width
                    height: Math.ceil(parent.height / 2)
                    y: 0
                }
                Rectangle {
                    id: bottom
                    color: root.fillColor
                    width: parent.width
                    height: parent.height - top.height
                    y: top.height
                }

                Timer {
                    id: delay
                    repeat: false
                    onTriggered: {
                        topAnim.restart()
                        bottomAnim.restart()
                    }
                }
                NumberAnimation {
                    id: topAnim
                    target: top
                    property: "y"
                    to: -top.height * 1.01
                    duration: root.stepRun
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: root.bezier
                    // Only one of the pair needs to report settlement for
                    // this column -- both start and run together.
                    onFinished: root._onColumnSettled()
                }
                NumberAnimation {
                    id: bottomAnim
                    target: bottom
                    property: "y"
                    to: root.height + bottom.height * 0.01
                    duration: root.stepRun
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: root.bezier
                }
            }
        }
    }
}
