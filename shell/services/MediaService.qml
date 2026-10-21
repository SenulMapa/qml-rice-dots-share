pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import "../core"

Singleton {
    id: root

    readonly property list<MprisPlayer> players: Mpris.players.values
    property MprisPlayer activePlayer: null
    property real position: 0
    property bool eventsEnabled: false

    // Test-only fake-media override (QMLRICE_FAKE_MEDIA=1), OFF by default and
    // therefore inert in the real shell -- there is no MPRIS-independent way
    // to drive `available`/`playing`/`artwork`/etc. from a render harness
    // otherwise, since they're all derived from the real activePlayer below.
    // Used by render-media-ring.qml to verify panels/DashboardMediaCard.qml's
    // circular art + spectrum ring against the REAL component instead of a
    // hand-rolled reproduction.
    readonly property bool debugFakeEnabled: Quickshell.env("QMLRICE_FAKE_MEDIA") === "1"
    property bool debugFakeAvailable: false
    property bool debugFakePlaying: false
    property string debugFakeTitle: "Fake Track"
    property string debugFakeArtist: "Fake Artist"
    property url debugFakeArtwork: ""

    // Env-gated event trace (QMLRICE_TRACE_MEDIA=1): which signal fired, with
    // what title and playback state at that instant, and whether a presentation
    // was queued or skipped. Costs nothing when unset.
    readonly property bool traceMedia: Quickshell.env("QMLRICE_TRACE_MEDIA") === "1"
    function traceEvent(what): void {
        if (traceMedia)
            console.log("MEDIA " + Date.now() + " " + what
                + " title=" + (activePlayer?.trackTitle || "")
                + " state=" + (activePlayer ? activePlayer.playbackState : "none")
                + " playing=" + playing + " events=" + eventsEnabled)
    }

    readonly property bool available: root.debugFakeEnabled
        ? root.debugFakeAvailable : activePlayer !== null
    readonly property int playerCount: players.length
    readonly property string identity: activePlayer?.identity || "Media"
    readonly property string title: root.debugFakeEnabled
        ? root.debugFakeTitle : (activePlayer?.trackTitle || "Unknown track")
    readonly property string artist: root.debugFakeEnabled
        ? root.debugFakeArtist : (activePlayer?.trackArtist || identity)
    readonly property string album: activePlayer?.trackAlbum || ""
    readonly property url artwork: root.debugFakeEnabled
        ? root.debugFakeArtwork : (activePlayer?.trackArtUrl || "")
    readonly property real duration: activePlayer?.lengthSupported
        ? Math.max(0, activePlayer.length) : 0
    readonly property real progress: duration > 0
        ? Math.max(0, Math.min(1, position / duration)) : 0
    readonly property bool playing: root.debugFakeEnabled
        ? root.debugFakePlaying
        : activePlayer?.playbackState === MprisPlaybackState.Playing
    readonly property bool paused: activePlayer?.playbackState
        === MprisPlaybackState.Paused
    readonly property bool canToggle: activePlayer?.canTogglePlaying ?? false
    readonly property bool canPrevious: activePlayer?.canGoPrevious ?? false
    readonly property bool canNext: activePlayer?.canGoNext ?? false
    readonly property bool canSeek: activePlayer?.canSeek ?? false
    readonly property bool hoverVisible: Config.media.hoverMode === "available"
        ? available : Config.media.hoverMode === "playing" ? playing : false

    signal presentationRequested()
    signal presentationDismissRequested()

    function isIdle(player: MprisPlayer): bool {
        return player !== null
            && player.playbackState === MprisPlaybackState.Stopped
            && !player.trackTitle && !player.trackArtist
    }

    function resolveActivePlayer(): void {
        const playingPlayer = Config.media.preferPlaying
            ? players.find(player => player && player.isPlaying) : null
        if (playingPlayer) {
            activePlayer = playingPlayer
            return
        }

        if (activePlayer && players.indexOf(activePlayer) >= 0 && !isIdle(activePlayer))
            return

        activePlayer = players.find(player => player && player.canControl
            && !isIdle(player)) || null
    }

    function selectPlayer(player: MprisPlayer): void {
        if (player && players.indexOf(player) >= 0)
            activePlayer = player
    }

    function selectNextPlayer(): void {
        if (players.length < 2)
            return
        const currentIndex = Math.max(0, players.indexOf(activePlayer))
        for (let offset = 1; offset <= players.length; ++offset) {
            const candidate = players[(currentIndex + offset) % players.length]
            if (candidate && !isIdle(candidate)) {
                activePlayer = candidate
                return
            }
        }
    }

    function setPresentationsEnabled(enabled: bool): void {
        SettingsStore.setMediaToggle("enabled", enabled)
        if (!enabled)
            presentationDismissRequested()
    }

    function setPreferPlaying(enabled: bool): void {
        if (SettingsStore.setMediaToggle("preferPlaying", enabled))
            resolveActivePlayer()
    }

    function setPresentationTimeout(milliseconds: real): void {
        SettingsStore.setMediaPresentationTimeout(milliseconds)
    }

    function setHoverMode(mode: string): void {
        SettingsStore.setMediaHoverMode(mode)
    }

    function resetPreferences(): void {
        SettingsStore.resetMedia()
        resolveActivePlayer()
    }

    function togglePlaying(): void {
        if (canToggle)
            activePlayer.togglePlaying()
        else if (playing && activePlayer?.canPause)
            activePlayer.pause()
        else if (activePlayer?.canPlay)
            activePlayer.play()
    }

    function previous(): void {
        if (canPrevious)
            activePlayer.previous()
    }

    function next(): void {
        if (canNext)
            activePlayer.next()
    }

    function seekTo(fraction: real): void {
        if (canSeek && duration > 0)
            activePlayer.position = Math.max(0, Math.min(1, fraction)) * duration
    }

    function refreshPosition(): void {
        position = activePlayer?.positionSupported
            ? Math.max(0, activePlayer.position) : 0
    }

    function queuePresentation(): void {
        const player = activePlayer
        if (eventsEnabled && player && player.trackTitle) {
            traceEvent("present:queued")
            presentationDebounce.restart()
        } else {
            traceEvent("present:skipped")
        }
    }

    onPlayersChanged: resolveActivePlayer()
    onActivePlayerChanged: {
        traceEvent("activePlayerChanged")
        refreshPosition()
        if (eventsEnabled)
            queuePresentation()
    }

    Instantiator {
        model: root.players
        delegate: Connections {
            required property MprisPlayer modelData
            target: modelData

            function onIsPlayingChanged(): void {
                root.resolveActivePlayer()
            }

            function onTrackChanged(): void {
                root.traceEvent("trackChanged")
                root.resolveActivePlayer()
                root.queuePresentation()
            }
        }
    }

    Connections {
        target: root.activePlayer

        function onPlaybackStateChanged(): void {
            root.traceEvent("playbackStateChanged")
            root.resolveActivePlayer()
            root.refreshPosition()
            // Present when playback STARTS or RESUMES, never on pause. This is
            // ChillPill's rule (its MprisModule fires only on a transition into
            // playing), and pausing is something the user just did themselves,
            // so a full media card confirming it is noise.
            if (root.playing)
                root.queuePresentation()
        }

        function onPositionChanged(): void {
            root.refreshPosition()
        }

        function onLengthChanged(): void {
            root.refreshPosition()
        }
    }

    Timer {
        id: positionTimer
        interval: Config.media.positionInterval
        repeat: true
        running: root.playing
        onTriggered: root.refreshPosition()
    }

    Timer {
        id: presentationDebounce
        interval: 180
        onTriggered: { root.traceEvent("presentationRequested"); root.presentationRequested() }
    }

    Timer {
        interval: 1000
        running: true
        onTriggered: {
            root.resolveActivePlayer()
            root.eventsEnabled = true
        }
    }
}
