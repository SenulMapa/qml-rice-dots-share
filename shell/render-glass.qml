// Real-compositor render harness for the glass redesign.
//
//   GLASS_TARGET=samples qs -p ./render-glass.qml
//
// Offscreen grabs can't show glass: the blur is Hyprland's, not ours. So this
// puts a test backdrop (tools/glass-backdrops/*.jpg) on screen as a Top layer
// and the component under test above it as an Overlay layer named
// "qml-rice:island" -- the glass layer rule then blurs the backdrop for real
// -- and screenshots the output with grim for each backdrop into
// /tmp/glass-review/<target>-<backdrop>.png, then quits.
//
// Both layers are click-through (empty input mask) and take no keyboard
// focus; nothing here locks, grabs input, or touches live system state. It
// does cover one monitor for ~6s, so run it when nobody is using the machine.
//
// GLASS_SCREEN picks the output (default: the first screen).
// GLASS_TARGET: samples | dashboard
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "components"
import "panels"
import "services"
import "core"

ShellRoot {
    id: root

    readonly property string target: Quickshell.env("GLASS_TARGET") || "samples"
    readonly property var screenObj: {
        const want = Quickshell.env("GLASS_SCREEN");
        return Quickshell.screens.find(s => s.name === want) || Quickshell.screens[0];
    }
    readonly property var backdrops: ["dark", "bright", "saturated", "whitepage"]
    property int index: 0
    readonly property string backdropName: backdrops[Math.min(index, backdrops.length - 1)]
    // Top-centre average of each test image (magick -resize 32x18! -crop
    // 12x4+10+0 -scale 1x1!), the same sample AdaptiveColor takes from a real
    // wallpaper, so the computed colours match the backdrop on screen.
    readonly property var backdropAverages: ({ dark: "#1c1b3d", bright: "#ede6f2", saturated: "#65518f", whitepage: "#e7f0f9" })
    onBackdropNameChanged: AdaptiveColor.overrideBackdrop = backdropAverages[backdropName]
    Component.onCompleted: AdaptiveColor.overrideBackdrop = backdropAverages[backdropName]

    PanelWindow {
        id: backdropWindow
        screen: root.screenObj
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "black"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "qml-rice:harness-backdrop"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region {}

        Image {
            anchors.fill: parent
            source: Qt.resolvedUrl("tools/glass-backdrops/" + root.backdropName + ".jpg")
            fillMode: Image.PreserveAspectCrop
        }
    }

    PanelWindow {
        id: glassWindow
        screen: root.screenObj
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "qml-rice:island"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region {}

        Loader {
            anchors.fill: parent
            sourceComponent: root.target === "dashboard" ? dashboardTarget : samplesTarget
        }
    }

    // ---- Targets ----

    Component {
        id: samplesTarget
        Item {
            // A panel, a row of toggles (alternating on/off), a capsule and
            // some text, centred near the top like the island's panels.
            Item {
                id: panel
                width: 760; height: 300
                x: (parent.width - width) / 2; y: 60
                GlassMaterial { anchors.fill: parent; radius: 34 }
                Column {
                    anchors.fill: parent
                    anchors.margins: 28
                    spacing: 18
                    Text {
                        text: "Glass material"
                        font.family: Theme.fontDisplay
                        font.pixelSize: 26; font.weight: Font.DemiBold
                        color: AdaptiveColor.glassText
                    }
                    Text {
                        text: "Real compositor blur, near-clear tint, lit rim — " + root.backdropName
                        font.family: Theme.fontUi
                        font.pixelSize: 15
                        color: AdaptiveColor.glassTextDim
                    }
                    Row {
                        spacing: 16
                        Repeater {
                            model: ["wifi", "bluetooth", "volume_up", "bedtime", "coffee", "notifications_off"]
                            delegate: Item {
                                required property string modelData
                                required property int index
                                width: 56; height: 56
                                GlassMaterial {
                                    anchors.fill: parent
                                    radius: 28
                                    active: parent.index % 2 === 0
                                    shadow: 0.08
                                }
                                Text {
                                    anchors.centerIn: parent
                                    text: parent.modelData
                                    font.family: "Material Symbols Rounded"
                                    font.pixelSize: 24
                                    color: parent.index % 2 === 0 ? AdaptiveColor.activeFillText : AdaptiveColor.glassText
                                }
                            }
                        }
                    }
                    Item {
                        width: parent.width; height: 44
                        GlassMaterial { anchors.fill: parent; radius: 22; shadow: 0.06 }
                        Rectangle {
                            width: parent.width * 0.62; height: parent.height
                            radius: 22
                            color: "white"
                        }
                        Text {
                            x: 16; anchors.verticalCenter: parent.verticalCenter
                            text: "volume_up"
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: 22
                            color: "#1c1c1e"
                        }
                    }
                }
            }
        }
    }

    Component {
        id: dashboardTarget
        Item {
            // The real dashboard panel inside a glass blob-like surface.
            Item {
                id: dash
                width: content.dashWidth + Theme.space2 * 2
                height: content.dashHeight + Theme.space2 * 2
                x: (parent.width - width) / 2; y: 8
                GlassMaterial { anchors.fill: parent; radius: Theme.radiusLarge }
                DashboardSlim {
                    id: content
                    anchors.fill: parent
                    availableWidth: 1200
                    availableHeight: 700
                }
            }
        }
    }

    // ---- Capture sequence ----

    Process {
        id: grim
        onExited: {
            root.index += 1;
            if (root.index < root.backdrops.length)
                settle.restart();
            else
                Qt.quit();
        }
    }

    Timer {
        id: settle
        interval: 1200
        running: true
        onTriggered: {
            grim.command = ["grim", "-o", root.screenObj.name,
                `/tmp/glass-review/${root.target}-${root.backdropName}.png`];
            grim.running = true;
        }
    }
}
