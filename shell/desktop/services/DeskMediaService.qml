// Desktop adapter over the shell's real services/MediaService.qml (MPRIS).
// Exposes impasto's MediaService-shaped API for faces/analogue/MediaFace and
// the modern faces' media rows.

pragma Singleton

import QtQuick
import Quickshell
import "../../services" as Shell

Singleton {
    id: root

    // Shell's own `available` is gated behind its QMLRICE_FAKE_MEDIA debug
    // flag; a real player counts here regardless of that flag.
    readonly property bool available: Shell.MediaService.playerCount > 0
        || Shell.MediaService.available
    readonly property string identity: Shell.MediaService.identity
    readonly property string title: Shell.MediaService.title
    readonly property string artist: Shell.MediaService.artist
    readonly property string album: Shell.MediaService.album
    readonly property url artUrl: Shell.MediaService.artwork
    readonly property real progress: Shell.MediaService.progress
    readonly property bool playing: Shell.MediaService.playing

    // Added for the dashboard port's MediaCard (bar/island/controls/
    // MediaCard.qml) transport row -- not read by any face this desktop
    // port shipped before, so these were not forwarded until now.
    readonly property real position: Shell.MediaService.position
    readonly property real length: Shell.MediaService.duration
    readonly property bool seekable: Shell.MediaService.canSeek
    // impasto's MediaModule detail card (island/cards/PlayerCard.qml) reads
    // both `seekable` (whether the progress row shows at all) and `canSeek`
    // (whether the drag handle is enabled) -- the shell's own MediaService
    // only has one flag, so both just alias it.
    readonly property bool canSeek: Shell.MediaService.canSeek

    function seek(fraction: real): void { Shell.MediaService.seekTo(fraction) }
    readonly property bool canPrevious: Shell.MediaService.canPrevious
    readonly property bool canNext: Shell.MediaService.canNext

    function toggle(): void { Shell.MediaService.togglePlaying() }
    function previous(): void { Shell.MediaService.previous() }
    function next(): void { Shell.MediaService.next() }
    // No-ops: the shell's MediaService has no subscribe/release lifecycle
    // (unlike DeskStatsService/DeskUpdatesService, which poll). Kept so
    // MediaCard's Component.onCompleted/onDestruction calls port unchanged.
    function subscribe(): void {}
    function release(): void {}
}
