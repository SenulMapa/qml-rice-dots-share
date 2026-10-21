// Visual verification harness for the BPM-synced VinylDisc spin and the
// new bottom-edge cava visualizer (visualizer/EdgeVisualizer.qml). Runs
// the REAL components against REAL MediaService/VisualizerService/
// TempoService state (does not touch playback) -- Spotify was already
// playing when this was written, so no synthetic feed is forced by
// default. Fully click-through, times out on its own; never touches the
// live `qs -p ./shell.qml` process.
//
// Run with: timeout 20 qs -p harness.qml
import QtQuick
import Quickshell
import Quickshell.Wayland
import "core"
import "components"
import "visualizer"
import "services"

ShellRoot {
    id: root

    Variants {
        model: Quickshell.screens

        EdgeVisualizer {
            required property var modelData
            screen: modelData
        }
    }

    // One small always-on-top panel showing the VinylDisc + tempo readout,
    // on the first screen only -- this is a debug probe, not a production
    // surface, so it does not need per-screen instantiation.
    PanelWindow {
        screen: Quickshell.screens[0]
        anchors { top: true; right: true }
        implicitWidth: 260
        implicitHeight: 320
        color: "#161318"
        WlrLayershell.namespace: "qml-rice:harness-probe"
        WlrLayershell.layer: WlrLayer.Overlay

        Column {
            anchors.centerIn: parent
            spacing: 12
            VinylDisc {
                width: 220
                height: 220
                playing: MediaService.playing
                artworkSource: MediaService.artwork
                onScreen: true
            }
            Text {
                color: "white"
                text: "playing=" + MediaService.playing
                    + " bpm=" + TempoService.bpm.toFixed(1)
                    + " avail=" + TempoService.available
                    + " smoothed=" + TempoService.smoothedBpm.toFixed(1)
            }
        }
    }

    Timer {
        interval: 19000
        running: true
        onTriggered: Qt.quit()
    }
}
