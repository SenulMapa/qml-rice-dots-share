import QtQuick
import QtQuick.Effects
import "../core"
import "../services"

/**
 * LyricWheel — a "wheel of options" (ported from React Bits' OptionWheel)
 * used as the slim dashboard's lyric readout. Rows now stack in a straight
 * top-to-bottom list (the wheel's curve/tilt was removed on 6 Oct); further
 * from the live line they dim, blur and fade into the edge feather.
 *
 * `pos` (a float row index) springs toward `target` via a critically-damped
 * spring (MotionValue with omega=9, zeta=1.0). The MotionValue only updates
 * while the spring is active, so an idle wheel costs nothing. Rows are drawn
 * from a small FIXED-size Repeater window (rowCount delegates) whose base
 * index tracks floor(pos) -- delegates are recycled by rebinding rowIndex,
 * never destroyed/recreated per frame, and only rows within `windowDist` of
 * pos are made visible.
 *
 * The whole wheel is masked by a vertical gradient (featherMask): opaque in
 * the middle, fading to transparent at the top and bottom edges over featherPx
 * pixels. The selected row glows with a soft shadow halo (glowStrength,
 * glowBlur). Blur is applied per-row via `layer.effect` (a MultiEffect), and
 * only while a row actually needs it (dist > 0.05), so a settled wheel with
 * 3-5 legible rows never carries more than one or two live blur layers.
 *
 * lines/index default to LyricsService (services/LyricsService.qml) but are
 * plain properties so a test harness can feed a fake array without a real
 * MPRIS session. Mouse wheel scrolls a PREVIEW target (previewIndex) so
 * neighbouring lines can be read ahead of/behind the live one; it snaps back
 * to the live index snapBackDelay ms after the last scroll. Clicking a row
 * seeks MediaService to that line's timestamp.
 */
Item {
    id: root

    clip: true

    // ---- data ----------------------------------------------------------
    // Lyrics and playback position from LyricsService.
    property var lines: LyricsService.lines
    property int liveIndex: LyricsService.index

    // ---- tunables --------------------------------------------------------
    property real spacing: 1.4             // row height = fontPx * spacing
    property real fade: 0.25               // opacity lost per unit of distance
    property real minOpacity: 0.05
    property real blurPxPerDist: 2         // px of blur per unit distance
    property real blurMaxPx: 16            // MultiEffect blurMax normaliser
    // Rows exist until they are fully past the box edge, where the feather
    // mask has already taken them to transparent. A fixed 3.5-row window was
    // fine on the curved wheel (rows bowed out of the box first), but on the
    // straight list it ended INSIDE a tall box, so lines popped in and out --
    // the "sharp cutoffs" the owner saw on 6 Oct.
    readonly property real windowDist: height / (2 * rowH) + 1
    readonly property int rowCount: Math.min(41, 2 * Math.ceil(windowDist) + 3)
    property real inset: Theme.space1      // left anchor for every row
    property int snapBackDelay: 2500       // ms after last scroll input

    property color textColor: AdaptiveColor.glassTextDim
    property color activeColor: AdaptiveColor.glassText
    property string fontFamily: Config.appearance.handFontFamily
    property int fontPx: Theme.dashCaption

    // Derived dimensions (must come after fontPx/spacing which they depend on).
    readonly property real rowH: fontPx * spacing

    // Feather and glow tunables (depend on rowH).
    // Feather depth as a share of the box, top and bottom, so it scales with
    // the dashboard instead of a fixed 1.6 rows (read as a hard edge when tall).
    property real featherRatio: 0.38
    readonly property real featherPx: height * featherRatio
    property real glowStrength: 0.55       // shadow opacity on selected row
    property real glowBlur: 0.8            // shadow blur radius on selected row

    // ---- preview / snap-back --------------------------------------------
    property int previewIndex: liveIndex
    property bool previewing: false
    readonly property real target: previewing
        ? Math.max(0, Math.min(Math.max(0, lines.length - 1), previewIndex))
        : liveIndex

    Timer {
        id: snapBackTimer
        interval: root.snapBackDelay
        onTriggered: root.previewing = false
    }

    // ---- spring-driven position -------------------------------------------
    // The spring snaps immediately on large seeks (> windowDist) to avoid
    // spinning through many rows; otherwise it springs with no overshoot.
    property MotionValue posSpring: MotionValue {
        unit: "ratio"
        omega: 9
        zeta: 1.0
    }

    readonly property real pos: posSpring.value
    readonly property bool settled: posSpring.atRest()

    // Update posSpring.target and snap on large distance changes.
    onTargetChanged: {
        posSpring.target = root.target
        // A big seek snaps instead of spinning through dozens of rows. snap()
        // once, never `immediate = true`: MotionValue snaps EVERY retarget
        // while that flag is set, so the wheel would stop gliding for good.
        if (Math.abs(root.target - posSpring.value) > root.windowDist)
            posSpring.snap()
    }

    Component.onCompleted: {
        posSpring.target = root.target
        posSpring.snap()
    }

    // Base row index of Repeater slot 0 -- tracks floor(pos) so delegates are
    // recycled (rebound) rather than the model being reset every frame.
    readonly property int _base: Math.floor(pos) - Math.floor(rowCount / 2)

    function _mixColor(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t,
                       a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t)
    }

    function _seekTo(rowIndex) {
        if (rowIndex < 0 || rowIndex >= root.lines.length)
            return
        const line = root.lines[rowIndex]
        if (!line || MediaService.duration <= 0)
            return
        MediaService.seekTo(line.t / MediaService.duration)
    }

    // Vertical gradient mask: transparent at edges, opaque in the middle.
    // Clamps gradient stops to [0, 0.5] to avoid inverted regions.
    Item {
        id: featherMask
        anchors.fill: parent
        visible: false
        layer.enabled: true

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: "#00ffffff" }
                GradientStop {
                    position: Math.max(0, Math.min(0.5, root.featherPx / root.height))
                    color: "#ffffffff"
                }
                GradientStop {
                    position: Math.max(0.5, Math.min(1.0, 1 - root.featherPx / root.height))
                    color: "#ffffffff"
                }
                GradientStop { position: 1.0; color: "#00ffffff" }
            }
        }
    }

    // Rows container with vertical feather mask applied via layer effect.
    Item {
        id: rows
        anchors.fill: parent

        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: featherMask
            maskThresholdMin: 0
            maskSpreadAtMin: 1
        }

        Repeater {
            model: root.rowCount

            delegate: Item {
                id: rowRoot
                required property int index

                readonly property int rowIndex: root._base + index
                readonly property bool inBounds: rowIndex >= 0 && rowIndex < root.lines.length
                readonly property real d: rowIndex - root.pos
                readonly property real dist: Math.abs(d)
                readonly property bool inWindow: inBounds && dist <= root.windowDist
                readonly property bool selected: inBounds && dist < 0.5

                // Straight list (owner, 6 Oct: "not circle lyrics, straight top to
                // bottom"): rows stack at a fixed pitch, no tilt, bow or rotation.
                readonly property real rowY: d * root.rowH

                readonly property string lineText: inBounds
                    ? (root.lines[rowIndex].text.length > 0
                        ? root.lines[rowIndex].text : LyricsService.noteGlyph)
                    : ""

                visible: inWindow
                width: root.width
                height: root.rowH
                x: 0
                y: root.height / 2 + rowY - height / 2

                Text {
                    id: label
                    text: rowRoot.lineText
                    x: root.inset
                    width: root.width - root.inset
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    transformOrigin: Item.Left
                    font.family: root.fontFamily
                    font.pixelSize: root.fontPx
                    font.weight: Font.Normal
                    scale: 1 + 0.08 * Math.max(0, 1 - Math.min(rowRoot.dist, 1))
                    color: root._mixColor(root.textColor, root.activeColor,
                        Math.max(0, 1 - Math.min(rowRoot.dist, 1)))
                    opacity: Math.max(root.minOpacity, 1 - rowRoot.dist * root.fade)

                    // Layer enabled when blurring or when selected (for glow).
                    layer.enabled: rowRoot.dist > 0.05 || rowRoot.selected

                    layer.effect: MultiEffect {
                        blurEnabled: true
                        blur: Math.min(1, (rowRoot.dist * root.blurPxPerDist) / root.blurMaxPx)
                        blurMax: root.blurMaxPx

                        // Glow halo on selected row only.
                        shadowEnabled: rowRoot.selected
                        shadowColor: root.activeColor
                        shadowOpacity: root.glowStrength * Math.max(0, 1 - rowRoot.dist * 2)
                        shadowBlur: root.glowBlur
                        shadowHorizontalOffset: 0
                        shadowVerticalOffset: 0
                        autoPaddingEnabled: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root._seekTo(rowRoot.rowIndex)
                    }
                }
            }
        }
    }

    // WheelHandler scrolls a preview target; snaps back to the live index
    // snapBackDelay ms after the last input. Same accumulate-then-step
    // pattern as dashboard/components/Carousel.qml, one line per 120.
    WheelHandler {
        id: wheelInput
        property real turned: 0
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            if (root.lines.length === 0)
                return
            const delta = event.angleDelta.x !== 0 ? event.angleDelta.x : event.angleDelta.y
            turned += delta
            while (Math.abs(turned) >= 120) {
                const step = turned < 0 ? 1 : -1
                const base = root.previewing ? root.previewIndex : root.liveIndex
                root.previewIndex = Math.max(0, Math.min(root.lines.length - 1, base + step))
                root.previewing = true
                turned -= 120 * Math.sign(turned)
            }
            snapBackTimer.restart()
        }
    }
}
