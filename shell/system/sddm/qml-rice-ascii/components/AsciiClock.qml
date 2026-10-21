// ╭──────────────────────────────────────────────────────────────────────────╮
// │   A S C I I   C L O C K                                                  │
// │   self-contained port of lock/AsciiLockSurface.qml's shader pipeline,    │
// │   for the SDDM greeter (no Quickshell, no shell Theme singleton -- the   │
// │   greeter runs as the `sddm` user and cannot see either).                │
// ╰──────────────────────────────────────────────────────────────────────────╯
//
// Same GPU pipeline as the lock, reused as-is: ONE ShaderEffect pass
// (../shaders/ascii-lock.frag.qsb), fed by a hidden clock-Text -> texture and
// a hidden glyph-atlas -> texture. See that file's own header for the full
// account of why this replaced an earlier multi-pass GridMesh pipeline, and
// shaders/ascii-lock.frag's header for the GLSL 100es/120 constraints
// (`qsb --glsl "100 es,120,150" --hlsl 50 --msl 12`).
//
// Geometry, wave/tilt/hue driving and failure containment are ported
// verbatim from lock/AsciiLockSurface.qml; `root._mouseX/_mouseY/_seconds`
// etc are driven from OUTSIDE this component (Main.qml owns the one
// MouseArea + FrameAnimation for the whole window) via the `rotX`/`rotY`/
// `hue`/`seconds` properties below, so multiple AsciiClock instances (one
// per monitor, see Main.qml) can share a single animation driver.

import QtQuick

Item {
    id: root

    // ---- driven from outside (Main.qml owns the shared animation) --------
    required property real seconds
    required property real rotX
    required property real rotY
    required property real hue

    // ---- palette (baked into theme.conf at install time, see Main.qml) ---
    property color colorA: "#ffb4ab"
    property color colorB: "#f4c46b"
    property color colorC: "#9eccf1"
    property color fallbackTextColor: "#e7eef0"

    // ---- fonts -- system-only (see install script header for the fc-list
    // check this was verified against) --------------------------------------
    property string fontMono: "JetBrains Mono"

    property string clockText: "88:88"

    readonly property alias shaderOk: root._shaderOk

    // ---- ascii charset (identical to the lock's -- 67 glyphs, emptiest to
    // densest) --------------------------------------------------------------
    readonly property string charset:
        " .'`^\",:;Il!i~+_-?][}{1)(|/tfjrxnuvczXYUJCLQ0OZmwqpdbkhao*#MW&8%B@$"
    readonly property int glyphCount: root.charset.length

    // ---- geometry: same clockAspect-forced stage box as the lock ----------
    readonly property real clockAspect: aspectProbe.contentHeight > 0
        ? aspectProbe.contentWidth / aspectProbe.contentHeight : 3.0

    readonly property int stageWidthMax: Math.round(root.width * 0.86)
    readonly property int stageHeightBudget: Math.round(root.height * 0.60)
    readonly property int stageWidth: Math.max(1, Math.round(
        Math.min(root.stageWidthMax, root.stageHeightBudget * root.clockAspect)))
    readonly property int stageHeight: Math.max(1, Math.round(root.stageWidth / root.clockAspect))
    readonly property int stageX: Math.round((root.width - root.stageWidth) / 2)
    readonly property int stageY: Math.round((root.height - root.stageHeight) / 2)

    // On-screen ascii cell size -- fixed, not Theme.u()-derived (no Theme
    // singleton here): 11px matches Theme.u(0.25) at the shell's default
    // density.
    readonly property int asciiCellPx: 11
    readonly property int atlasCellPx: 64

    Text {
        id: aspectProbe
        x: -100000
        y: -100000
        visible: false
        text: "88:88"
        font.family: root.fontMono
        font.weight: Font.DemiBold
        font.pixelSize: 200
    }

    Text {
        id: clockTextItem
        x: -100000
        y: -100000
        width: root.stageWidth
        height: root.stageHeight
        text: root.clockText
        color: "#ffffff"
        font.family: root.fontMono
        font.weight: Font.DemiBold
        font.pixelSize: root.stageHeight
        fontSizeMode: Text.Fit
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter

        onTextChanged: clockTexSource.scheduleUpdate()
        onWidthChanged: clockTexSource.scheduleUpdate()
        onHeightChanged: clockTexSource.scheduleUpdate()
    }

    ShaderEffectSource {
        id: clockTexSource
        sourceItem: clockTextItem
        hideSource: false
        live: false
        smooth: true
        wrapMode: ShaderEffectSource.ClampToEdge
        width: clockTextItem.width
        height: clockTextItem.height
        visible: false
    }

    Item {
        id: atlasHost
        x: -100000
        y: -100000
        width: root.glyphCount * root.atlasCellPx
        height: root.atlasCellPx

        Row {
            Repeater {
                model: root.glyphCount
                delegate: Text {
                    id: glyphDelegate
                    required property int index
                    width: root.atlasCellPx
                    height: root.atlasCellPx
                    clip: true
                    text: root.charset.charAt(index)
                    color: "#ffffff"
                    font.family: root.fontMono
                    font.weight: Font.DemiBold
                    font.pixelSize: Math.round(root.atlasCellPx * 0.85)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }

    ShaderEffectSource {
        id: glyphAtlasSource
        sourceItem: atlasHost
        hideSource: false
        live: false
        smooth: true
        wrapMode: ShaderEffectSource.ClampToEdge
        width: atlasHost.width
        height: atlasHost.height
        visible: false
    }

    Timer {
        interval: 32
        running: true
        repeat: false
        onTriggered: glyphAtlasSource.scheduleUpdate()
    }

    ShaderEffect {
        id: asciiEffect
        x: root.stageX
        y: root.stageY
        width: root.stageWidth
        height: root.stageHeight
        visible: root._shaderOk

        property variant source: clockTexSource
        property variant atlas: glyphAtlasSource
        property size uResolution: Qt.size(root.stageWidth, root.stageHeight)
        property real uCellPx: root.asciiCellPx
        property real uGlyphCount: root.glyphCount
        property real uLumThreshold: 0.14

        property real uTime: root.seconds
        property real uK: 1.0
        property point uRot: Qt.point(root.rotX, root.rotY)
        property real uPerspective: 1.1

        property point uChroma: Qt.point(0.0012, 0.0)
        property point uDilate: Qt.point(
            (root.asciiCellPx * 2.1) / Math.max(root.stageWidth, 1),
            (root.asciiCellPx * 2.1) / Math.max(root.stageHeight, 1))
        property point uGlyphDilate: Qt.point(
            5.0 / (root.glyphCount * root.atlasCellPx),
            5.0 / root.atlasCellPx)

        property color colorA: root.colorA
        property color colorB: root.colorB
        property color colorC: root.colorC
        property real uHue: root.hue

        fragmentShader: Qt.resolvedUrl("../shaders/ascii-lock.frag.qsb")
    }

    // ---- failure containment: plain Text fallback, identical contract to
    // the lock's -- a broken ShaderEffect on a login screen would be just as
    // catastrophic as on the lock screen. ------------------------------------
    property bool _shaderOk: true

    Text {
        id: fallbackText
        x: root.stageX
        y: root.stageY
        width: root.stageWidth
        height: root.stageHeight
        visible: !root._shaderOk
        text: root.clockText
        color: root.fallbackTextColor
        font.family: root.fontMono
        font.weight: Font.DemiBold
        font.pixelSize: root.stageHeight
        fontSizeMode: Text.Fit
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    Connections {
        target: asciiEffect
        function onStatusChanged() {
            if (asciiEffect.status === ShaderEffect.Error) {
                console.warn("qml-rice-ascii greeter: shader failed to load, "
                    + "falling back to plain time text")
                root._shaderOk = false
            }
        }
    }
}
