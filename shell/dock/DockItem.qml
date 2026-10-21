import QtQuick
import QtQuick.Effects
import Quickshell
import "../core"
import "../services"
import "../components"
import "magnify.js" as Mag

/**
 * DockItem -- one icon: image, running dot, launch bounce, press darken.
 *
 * Geometry is driven by DockSurface: `size` is the current (magnified) icon
 * edge in px and the item's own box is size x size with its bottom edge on
 * the dock baseline, so the icon grows upward like the macOS dock. The dot
 * stays on the baseline while the icon bounces.
 *
 * The icon is requested once at the largest size it can ever be drawn at
 * (peak scale, x2 for crisp downscaling) and then only scaled by the scene
 * graph with mipmaps, so magnifying never reloads or re-rasterises it.
 */
Item {
    id: root

    property var model: ({})            // one DockModel item
    property real size: 48              // current icon edge px
    property real baseSize: 48          // resting icon edge px
    property real dockScale: 1
    property bool pressed: false
    property bool hovered: false
    property bool dragging: false
    property bool appear: true          // animate in when created
    property real peakScale: DockMetrics.peakScale

    readonly property bool isMinimized: model.kind === "minimized"
    readonly property bool launching: model.launching === true
    // Visual size correction for the theme's plate (DockMetrics.iconVisualScale).
    readonly property real visualScale: DockMetrics.iconVisualScale[model.icon] ?? 1
    readonly property var visualOffset: DockMetrics.iconVisualOffset[model.icon] ?? [0, 0]
    readonly property real _loadPx: Math.ceil(baseSize * peakScale * 2)

    width: size
    height: size

    // ---- icon source ----
    function iconSource(name): string {
        const n = String(name || "")
        if (n.length === 0 || (n.charAt(0) !== "/" && n.indexOf(":") < 0 && Quickshell.iconPath(n, true) === ""))
            return "image://icon/application-x-executable"
        if (n.charAt(0) === "/") return "file://" + n
        if (n.indexOf("file:") === 0 || n.indexOf("image:") === 0) return n
        return "image://icon/" + n
    }

    // ---- bounce ----
    property real bounceT: 0
    readonly property real lift: launching
        ? Mag.bounce(bounceT, { bouncePeriod: DockMetrics.bouncePeriod, bounceRestFraction: DockMetrics.bounceRestFraction,
                                bounceHeight: DockMetrics.bounceHeight }) * baseSize * 1.0
        : 0
    onLaunchingChanged: bounceT = 0
    FrameAnimation {
        running: root.launching
        onTriggered: root.bounceT += frameTime
    }

    Item {
        id: iconBox
        width: root.size; height: root.size
        y: -root.lift
        opacity: root.dragging ? 0.9 : 1
        property real appearScale: root.appear ? 0.2 : 1
        scale: appearScale
        transformOrigin: Item.Bottom
        Behavior on appearScale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
        Component.onCompleted: appearTimer.start()
        Timer { id: appearTimer; interval: 1; onTriggered: iconBox.appearScale = 1 }

        Image {
            id: img
            anchors.centerIn: parent
            width: parent.width; height: parent.height
            // Optical centring: the glyph offset in the theme image, in icon sizes.
            anchors.horizontalCenterOffset: root.visualOffset[0] * parent.width
            anchors.verticalCenterOffset: root.visualOffset[1] * parent.height
            source: root.iconSource(root.model.icon)
            sourceSize: Qt.size(root._loadPx, root._loadPx)
            fillMode: Image.PreserveAspectFit
            scale: root.visualScale
            transformOrigin: Item.Center
            smooth: true
            mipmap: true
            asynchronous: true
            cache: true
            layer.enabled: root.pressed || darken.opacity > 0.001
            layer.effect: MultiEffect {
                brightness: -DockMetrics.pressDarken * darken.opacity
            }
            // Fallback when the theme has no such icon.
            onStatusChanged: if (status === Image.Error && source != "image://icon/application-x-executable")
                source = "image://icon/application-x-executable"
        }
        Item {
            id: darken
            opacity: root.pressed ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: root.pressed ? 60 : 160; easing.type: Easing.OutQuad } }
        }
    }

    // ---- running indicator ----
    // A 4 px white dot, centred 5 px below the icon's bottom (dotGap 3 + radius 2),
    // inside the shelf's bottom padding.
    Rectangle {
        id: dot
        readonly property real d: DockMetrics.dotSize * root.dockScale
        visible: root.model.kind === "app" && root.model.running === true
        width: d; height: d; radius: d / 2
        x: (root.width - width) / 2
        y: root.height + DockMetrics.dotGap * root.dockScale
        color: Qt.rgba(1, 1, 1, DockMetrics.dotAlpha)
    }
}
