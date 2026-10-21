pragma ComponentBehavior: Bound
import QtQuick
import "../core"
import "../services"

/**
 * GlassClock3D -- the lock screen's "glass slabs" clock (glass redesign
 * Phase 5): frosted glass digits with visible thickness that tilt toward
 * the pointer like an Apple TV icon, drift slowly when nothing moves, and
 * flip a digit on its horizontal axis when it changes.
 *
 * How the depth is faked in a 2D scene graph:
 *   - The whole stage (side walls + face) is one item rotated about X and
 *     Y with real perspective (Rotation.distanceToPlane), so it foreshortens.
 *   - The slab's side wall is `layers` copies of the digits behind the
 *     face, each pushed further along the direction the tilt would reveal
 *     the back, fading out -- together they read as the glass edge.
 *   - The face is a LiquidGlass over `backgroundItem`; its light direction
 *     turns against the tilt, so the specular rim slides across the digits
 *     as the slab turns (the light stays put, the surface moves).
 * The frosted face samples the background flat, before the 3D turn; at
 * these angles (<= maxTilt) the mismatch is lost in the frost.
 *
 * Digits sit in fixed-width cells (widest digit), so changing time never
 * shifts the layout.
 */
Item {
    id: root

    required property Item backgroundItem
    property date now: new Date()
    property real pixelSize: 210
    property string fontFamily: Theme.fontClock
    // Pointer in this item's coordinates; null = no pointer (idle drift).
    property var pointer: null
    property bool tilt: true
    property bool reducedMotion: false
    property real maxTilt: 6
    property int layers: 10
    property real depth: 14

    readonly property string text: Qt.formatTime(now, "HH:mm")

    implicitWidth: face.width
    implicitHeight: face.height

    // ---- Tilt ----
    property bool _idle: true
    onPointerChanged: { _idle = pointer === null; idleTimer.restart(); }
    Timer { id: idleTimer; interval: 2500; onTriggered: root._idle = true }

    // The idle drift re-renders the 10 side-wall layers and the LiquidGlass
    // face every frame, for as long as the lock is up. It runs only while
    // shown and not on battery; on battery the slab holds its pose and only
    // the (event-driven) pointer tilt moves it.
    property real _phase: 0
    NumberAnimation on _phase {
        from: 0; to: Math.PI * 2; duration: 9000
        loops: Animation.Infinite
        running: root.tilt && !root.reducedMotion && root._idle && root.visible
            && !BatteryService.onBattery
    }

    readonly property real _targetPitch: !tilt || reducedMotion ? 0
        : _idle || !pointer ? 2 * Math.sin(_phase)
        : Math.max(-maxTilt, Math.min(maxTilt, -(pointer.y - height / 2) / (height * 2.2) * maxTilt * 2))
    readonly property real _targetYaw: !tilt || reducedMotion ? 0
        : _idle || !pointer ? 1.3 * Math.cos(_phase)
        : Math.max(-maxTilt, Math.min(maxTilt, (pointer.x - width / 2) / (width * 0.9) * maxTilt * 2))

    property real pitch: _targetPitch
    property real yaw: _targetYaw
    Behavior on pitch { SmoothedAnimation { velocity: 9 } }
    Behavior on yaw { SmoothedAnimation { velocity: 9 } }

    readonly property real _pr: pitch * Math.PI / 180
    readonly property real _yr: yaw * Math.PI / 180

    // ---- Digits ----
    TextMetrics { id: digitM; font.family: root.fontFamily; font.pixelSize: root.pixelSize; font.weight: Font.DemiBold; text: "0" }
    TextMetrics { id: colonM; font.family: root.fontFamily; font.pixelSize: root.pixelSize; font.weight: Font.DemiBold; text: ":" }
    readonly property real cellW: Math.max(digitM.advanceWidth, 1) * 1.02
    readonly property real colonW: colonM.advanceWidth * 1.15

    // One shared state per character position: what is shown and its flip
    // angle, read by the face and every side-wall layer alike.
    property var shown: ["0", "0", ":", "0", "0"]
    property var angles: [0, 0, 0, 0, 0]
    function _setAngle(i, a) { const n = angles.slice(); n[i] = a; angles = n; }
    function _setShown(i, c) { const n = shown.slice(); n[i] = c; shown = n; }

    onTextChanged: {
        for (let i = 0; i < 5; i++) {
            const c = text.charAt(i);
            if (c !== shown[i]) {
                const f = flips.itemAt(i);
                if (reducedMotion || !visible || !f) _setShown(i, c);
                else f.flipTo(c);
            }
        }
    }
    Component.onCompleted: shown = text.split("")

    Repeater {
        id: flips
        model: 5
        delegate: Item {
            id: flip
            required property int index
            property string next: ""
            property real a: 0
            onAChanged: root._setAngle(index, a)
            function flipTo(c) { next = c; anim.restart(); }
            SequentialAnimation {
                id: anim
                NumberAnimation { target: flip; property: "a"; from: 0; to: 90; duration: 200; easing.type: Easing.InCubic }
                ScriptAction { script: root._setShown(flip.index, flip.next) }
                NumberAnimation { target: flip; property: "a"; from: -90; to: 0; duration: 220; easing.type: Easing.OutCubic }
            }
        }
    }

    component Digits: Row {
        id: digits
        property color color: "white"
        Repeater {
            model: 5
            delegate: Item {
                id: cell
                required property int index
                width: index === 2 ? root.colonW : root.cellW
                height: root.pixelSize * 1.2
                Text {
                    anchors.centerIn: parent
                    text: root.shown[cell.index]
                    font.family: root.fontFamily
                    font.pixelSize: root.pixelSize
                    font.weight: Font.DemiBold
                    color: digits.color
                    transform: Rotation {
                        origin.x: cell.width / 2
                        origin.y: cell.height / 2
                        axis { x: 1; y: 0; z: 0 }
                        angle: root.angles[cell.index]
                    }
                }
            }
        }
    }

    // ---- Stage: side walls + glass face, turned together ----
    Item {
        id: stage
        width: face.width
        height: face.height
        transform: [
            Rotation {
                origin.x: stage.width / 2; origin.y: stage.height / 2
                axis { x: 1; y: 0; z: 0 }
                angle: root.pitch
                distanceToPlane: 1400
            },
            Rotation {
                origin.x: stage.width / 2; origin.y: stage.height / 2
                axis { x: 0; y: 1; z: 0 }
                angle: root.yaw
                distanceToPlane: 1400
            }
        ]

        // Side walls, back to front. A tilt reveals the back of the slab on
        // the side turning away, so the layers step opposite the turn.
        Repeater {
            model: root.layers
            delegate: Digits {
                required property int index
                // k: 1 = deepest layer, 1/layers = just behind the face.
                readonly property real k: (root.layers - index) / root.layers
                // Resting view looks slightly down-right into the slab; the
                // tilt swings the revealed edge around.
                readonly property real dx: (0.35 - Math.sin(root._yr) * 6) * root.depth * k
                readonly property real dy: (0.55 + Math.sin(root._pr) * 6) * root.depth * k
                x: (face.width - implicitWidth) / 2 + dx
                y: (face.height - implicitHeight) / 2 + dy
                // Brighter toward the face: the lit glass edge; darker and
                // fainter toward the back.
                color: Qt.rgba(0.92, 0.95, 1, 0.07 + 0.16 * (1 - k))
            }
        }

        LiquidGlass {
            id: face
            backgroundItem: root.backgroundItem
            width: faceDigits.implicitWidth + 120
            height: faceDigits.implicitHeight + 40
            frostRadius: 56
            milk: 0.3
            strength: 8
            edgeRadius: 7
            rim: 1.0
            lightDir: Qt.vector2d(-0.55 - root.yaw / root.maxTilt * 0.45,
                                  -0.85 + root.pitch / root.maxTilt * 0.45)

            Digits {
                id: faceDigits
                anchors.centerIn: parent
            }
        }
    }
}
