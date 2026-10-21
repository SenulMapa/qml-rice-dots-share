import QtQuick
import "../core"
import "../components"

/**
 * MacCcNowPlaying -- the Now Playing module (spec 3.4): 138 x 139 glass rounded
 * rectangle, two pill rows high. Artwork at the top left, the title, then the
 * previous / play-pause / next transport. Every value comes from MacTokens.
 *
 * The caller wires the three signals to MediaService. Nothing here plays,
 * pauses or seeks by itself. The transport stays at full strength while idle
 * (as the capture does); only the hit areas follow canPrevious / canNext.
 */
TahoeSurface {
    id: root

    property string title: ""
    property url artwork: ""
    property bool playing: false
    property bool available: false
    property bool canPrevious: false
    property bool canNext: false

    signal previousRequested()
    signal toggleRequested()
    signal nextRequested()

    readonly property real centreX: width / 2
    readonly property real transportY: MacTokens.s(MacTokens.ccTransportY)
    readonly property real spacing: MacTokens.s(MacTokens.ccTransportSpacing)
    readonly property real hitHalf: MacTokens.s(MacTokens.ccTransportHit) / 2

    kind: "controlcenter"
    fill: MacTokens.ccModuleFill
    width: MacTokens.s(MacTokens.ccNowPlayingWidth)
    height: MacTokens.s(MacTokens.ccNowPlayingHeight)
    radius: MacTokens.s(MacTokens.ccNowPlayingRadius)

    // Artwork, or a flat disc with a note when there is none.
    Rectangle {
        id: art
        x: MacTokens.s(MacTokens.ccArtInset)
        y: MacTokens.s(MacTokens.ccArtInset)
        width: MacTokens.s(MacTokens.ccArtSize)
        height: width
        radius: MacTokens.s(MacTokens.ccArtRadius)
        color: MacTokens.ccDiscIdleFill
        clip: true

        Image {
            id: artImage
            anchors.fill: parent
            source: root.artwork
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
    }

    Text {
        x: MacTokens.s(MacTokens.ccArtInset)
        y: MacTokens.s(MacTokens.ccNowPlayingTitleY)
        width: root.width - 2 * MacTokens.s(MacTokens.ccArtInset)
        text: root.available && root.title !== "" ? root.title : "Not Playing"
        color: MacTokens.ccTitleColor
        elide: Text.ElideRight
        font.family: MacTokens.textFamily
        font.pixelSize: MacTokens.s(MacTokens.ccTitleSize)
        font.weight: Font.DemiBold
    }

    // Transport. Each glyph has a square hit area (ccTransportHit) around its centre.
    Icon {
        id: prevGlyph
        x: root.centreX - root.spacing - width / 2
        y: root.transportY - height / 2
        name: "transport/prev"
        size: MacTokens.s(MacTokens.ccTransportSize)
        color: MacTokens.ccActiveFill
    }
    MouseArea {
        x: prevGlyph.x + prevGlyph.width / 2 - root.hitHalf
        y: root.transportY - root.hitHalf
        width: root.hitHalf * 2
        height: root.hitHalf * 2
        enabled: root.available && root.canPrevious
        onClicked: root.previousRequested()
    }

    Icon {
        id: playGlyph
        x: root.centreX - width / 2
        y: root.transportY - height / 2
        name: root.playing ? "transport/pause" : "transport/play"
        size: MacTokens.s(MacTokens.ccPlaySize)
        color: MacTokens.ccActiveFill
    }
    MouseArea {
        x: root.centreX - root.hitHalf
        y: root.transportY - root.hitHalf
        width: root.hitHalf * 2
        height: root.hitHalf * 2
        enabled: root.available
        onClicked: root.toggleRequested()
    }

    Icon {
        id: nextGlyph
        x: root.centreX + root.spacing - width / 2
        y: root.transportY - height / 2
        name: "transport/next"
        size: MacTokens.s(MacTokens.ccTransportSize)
        color: MacTokens.ccActiveFill
    }
    MouseArea {
        x: nextGlyph.x + nextGlyph.width / 2 - root.hitHalf
        y: root.transportY - root.hitHalf
        width: root.hitHalf * 2
        height: root.hitHalf * 2
        enabled: root.available && root.canNext
        onClicked: root.nextRequested()
    }
}
