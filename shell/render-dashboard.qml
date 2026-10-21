// Headless-ish render harness for the dashboard typography pass.
//
// Run with:  qs -p ./render-dashboard.qml
//
// Lives at the config root (not tools/) for the same reason run-tests.sh's
// test-*.qml files do: Quickshell resolves relative imports from the
// importing file's own directory and refuses to traverse ".." out of the
// config subtree, so a harness in a subdirectory can't reach "../panels"'s
// own "../components"/"../core" imports.
//
// Instantiates the REAL panels/Dashboard.qml (with real Theme/Config tokens
// and the real live singleton services -- not mocks) inside an offscreen
// FloatingWindow sized to the real 789x440 dashboard surface, then:
//   1. Walks the item tree and logs every Text's font.family, font.pixelSize,
//      font.weight, font.bold, paintedWidth/paintedHeight, and the available
//      width of its parent (so overflow is visible in the log, not just the
//      PNG).
//   2. Renders a small side-by-side swatch strip of Bricolage Grotesque at several
//      weights (and the outline-stroke technique) so synthetic-bold
//      behaviour can be read directly off the pixels.
//   3. grabToImage()s the whole window to /tmp/dashrender/*.png.
//
// No screen capture (grim) is used anywhere -- grabToImage renders the QML
// item tree itself, not the physical display.
import QtQuick
import QtQuick.Layouts
import Quickshell
import "core"
import "panels"

FloatingWindow {
    id: window
    title: "dashboard render harness"
    implicitWidth: 900
    implicitHeight: 900

    // Tag set from the command line via IPC-free env var so before/after
    // renders land in different files without editing this script.
    readonly property string tag: (Quickshell.env("DASHRENDER_TAG") || "render")

    Rectangle {
        id: grabRoot
        anchors.fill: parent
        color: "#0b0b0e"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12

            // ---- 1. Bricolage Grotesque weight/technique swatch strip ----
            Rectangle {
                id: swatch
                Layout.preferredWidth: 789
                Layout.preferredHeight: 210
                color: "#17151b"
                radius: 8

                Column {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 4

                    Repeater {
                        model: [
                            { label: "Normal 18px", weight: Font.Normal, outline: false },
                            { label: "Medium 18px", weight: Font.Medium, outline: false },
                            { label: "DemiBold 18px", weight: Font.DemiBold, outline: false },
                            { label: "Bold 18px", weight: Font.Bold, outline: false },
                            { label: "Black 18px", weight: Font.Black, outline: false },
                            { label: "DemiBold 18px + outline", weight: Font.DemiBold, outline: true },
                            { label: "Bold 18px + outline", weight: Font.Bold, outline: true }
                        ]
                        delegate: Row {
                            spacing: 10
                            required property var modelData
                            Text {
                                width: 220
                                text: modelData.label
                                color: "#8a8790"
                                font.family: Config.appearance.monoFontFamily
                                font.pixelSize: 10
                            }
                            Text {
                                id: swatchText
                                text: "Dashboard 24°"
                                color: "#e6e1e9"
                                font.family: "Bricolage Grotesque"
                                font.pixelSize: 18
                                font.weight: modelData.weight
                                style: modelData.outline ? Text.Outline : Text.Normal
                                styleColor: "#e6e1e9"
                                Component.onCompleted: root.logText(swatchText, "swatch:" + modelData.label)
                            }
                        }
                    }
                }
            }

            // ---- 2. Real dashboard, real size ----
            Rectangle {
                id: dashboardFrame
                Layout.preferredWidth: 789
                Layout.preferredHeight: 440
                color: "#121217"
                radius: 12
                clip: true

                Dashboard {
                    id: dashboard
                    anchors.fill: parent
                    anchors.margins: 8
                }
            }
        }
    }

    QtObject {
        id: root

        function logText(item, tag) {
            console.log(JSON.stringify({
                tag: tag,
                family: item.font.family,
                pixelSize: item.font.pixelSize,
                weight: item.font.weight,
                bold: item.font.bold,
                paintedWidth: Math.round(item.paintedWidth),
                paintedHeight: Math.round(item.paintedHeight)
            }))
        }

        // Recursively walk the item tree under `node`, logging every Text.
        function walk(node, path) {
            for (let i = 0; i < node.children.length; i++) {
                const child = node.children[i]
                const childPath = path + "/" + (child.objectName || child.toString())
                if (child.toString().indexOf("QQuickText(") === 0
                        || child.toString().indexOf("Text_QMLTYPE") === 0
                        || (child.text !== undefined && child.font !== undefined
                            && child.paintedWidth !== undefined)) {
                    const availW = child.parent ? Math.round(child.parent.width) : -1
                    console.log(JSON.stringify({
                        tag: "dashboard-text",
                        path: childPath,
                        text: (child.text || "").toString().slice(0, 24),
                        family: child.font.family,
                        pixelSize: child.font.pixelSize,
                        weight: child.font.weight,
                        bold: child.font.bold,
                        paintedWidth: Math.round(child.paintedWidth),
                        paintedHeight: Math.round(child.paintedHeight),
                        parentAvailWidth: availW,
                        overflow: availW > 0 && child.paintedWidth > availW
                    }))
                }
                if (child.children && child.children.length > 0)
                    walk(child, childPath)
            }
        }
    }

    // Give async icon fonts / artwork / layout a moment to settle before
    // measuring or grabbing -- this is a real live-service tree, not a
    // static fixture.
    Timer {
        interval: 1800
        running: true
        repeat: false
        onTriggered: {
            console.log("=== dashboard text inventory (" + window.tag + ") ===")
            root.walk(dashboardFrame, "dashboard")
            console.log("=== grabbing " + window.tag + " ===")
            grabRoot.grabToImage(function(result) {
                const path = "/tmp/dashrender/" + window.tag + ".png"
                if (result.saveToFile(path))
                    console.log("SAVED " + path)
                else
                    console.log("SAVE_FAILED " + path)
                Qt.callLater(Qt.quit)
            })
        }
    }
}
