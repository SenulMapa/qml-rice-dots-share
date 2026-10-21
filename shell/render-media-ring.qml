// Visual verification harness for the dashboard Now Playing card's circular
// art + spectrum ring (panels/DashboardMediaCard.qml). Instantiates the REAL
// DashboardMediaCard (not a reproduction) and grabs it TWICE from the same
// frame/instance -- once idle, once with services/MediaService.qml's
// debugFake* override flipped on -- so both grabs are guaranteed to be at
// identical scale. The two PNGs are then montaged side by side by the
// caller (see run comment below); this file only produces the two frames.
//
// MediaService is entirely MPRIS-derived and has no writable
// available/playing/artwork properties to poke from outside, so this relies
// on MediaService.qml's own debugFake* override block, which is OFF (and
// therefore inert in the real shell) unless QMLRICE_FAKE_MEDIA=1 is set in
// the environment this harness runs under.
//
// Run with:
//   QMLRICE_FAKE_MEDIA=1 qs -p ./render-media-ring.qml
//   magick /tmp/dashrender/media-ring2-idle.png \
//     /tmp/dashrender/media-ring2-playing.png +append \
//     /tmp/dashrender/media-ring2.png
import QtQuick
import QtQuick.Layouts
import Quickshell
import "core"
import "panels"
import "services"

FloatingWindow {
    id: window
    title: "media ring render harness"
    implicitWidth: 420
    implicitHeight: 220

    Component.onCompleted: {
        if (!MediaService.debugFakeEnabled) {
            console.log("WARN: QMLRICE_FAKE_MEDIA=1 not set -- both grabs "
                + "will render idle")
        }
        MediaService.debugFakeTitle = "Radial Ring"
        MediaService.debugFakeArtist = "Fake Artist"
        MediaService.debugFakeArtwork = "file:///tmp/dashrender/fake-art.png"
    }

    Rectangle {
        id: cardFrame
        anchors.fill: parent
        color: "#121217"
        radius: 12
        clip: true
        DashboardMediaCard {
            id: card
            anchors.fill: parent
            anchors.margins: 4
        }
    }

    // Feed a fake 64-bin spectrum directly into VisualizerService's own
    // writable backing property, exactly like a live cava frame would
    // (parseSpectrumFrame does the same _spectrum = [...] assignment).
    Timer {
        interval: 16
        running: true
        repeat: true
        property real t: 0
        onTriggered: {
            t += 0.05
            const bars = []
            for (let i = 0; i < VisualizerService.spectrumBarCount; i++) {
                const phase = i / VisualizerService.spectrumBarCount
                const v = 0.5 + 0.5 * Math.sin(t * 2 + phase * Math.PI * 6)
                bars.push(Math.max(0, Math.min(1, v)))
            }
            VisualizerService._spectrum = bars
            VisualizerService.spectrumAvailable = true
        }
    }

    // ---- Grab 1: idle (fake override still false) ----
    Timer {
        interval: 900
        running: true
        repeat: false
        onTriggered: {
            console.log("=== grabbing idle ===")
            cardFrame.grabToImage(function(result) {
                const path = "/tmp/dashrender/media-ring2-idle.png"
                if (result.saveToFile(path))
                    console.log("SAVED " + path)
                else
                    console.log("SAVE_FAILED " + path)

                // ---- flip to playing, then grab 2 after it settles ----
                MediaService.debugFakeAvailable = true
                MediaService.debugFakePlaying = true
            })
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: false
        onTriggered: {
            console.log("=== grabbing playing ===")
            cardFrame.grabToImage(function(result) {
                const path = "/tmp/dashrender/media-ring2-playing.png"
                if (result.saveToFile(path))
                    console.log("SAVED " + path)
                else
                    console.log("SAVE_FAILED " + path)
                Qt.callLater(Qt.quit)
            })
        }
    }
}
