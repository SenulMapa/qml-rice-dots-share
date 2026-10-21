pragma Singleton
import QtQuick
import Quickshell.Io
import Quickshell.Services.Pipewire
import "../core"

QtObject {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property bool available: Pipewire.ready && sink?.audio !== null && sink?.audio !== undefined
    readonly property bool microphoneAvailable: Pipewire.ready
        && source?.audio !== null && source?.audio !== undefined
    readonly property real volume: available ? sink.audio.volume : 0
    readonly property int volumePercent: Math.round(volume * 100)
    readonly property bool muted: available ? sink.audio.muted : false
    readonly property real microphoneVolume: microphoneAvailable ? source.audio.volume : 0
    readonly property int microphonePercent: Math.round(microphoneVolume * 100)
    readonly property bool microphoneMuted: microphoneAvailable ? source.audio.muted : false
    readonly property string outputName: displayName(sink, "No output")
    readonly property string inputName: displayName(source, "No microphone")
    readonly property var outputDevices: Pipewire.nodes.values.filter(node =>
        node?.audio && node.isSink && !node.isStream)
    readonly property var inputDevices: Pipewire.nodes.values.filter(node =>
        node?.audio && !node.isSink && !node.isStream)

    // Per-app playback streams (Pipewire sink-inputs). Filtered on the node
    // type only: a node's audio properties aren't valid until it is bound by
    // streamTracker below, so requiring `audio` here would never pass.
    readonly property var playbackStreams: Pipewire.nodes.values.filter(node =>
        node?.isStream && (node.type & PwNodeType.AudioOutStream))

    property PwObjectTracker streamTracker: PwObjectTracker {
        objects: root.playbackStreams
    }

    property bool eventsEnabled: false
    property bool outputEventScheduled: false
    property bool microphoneEventScheduled: false

    // Set true (by setVolumeFromEdge below) just before an edge-scroll
    // change writes sink.audio.volume, and read+cleared the moment the
    // resulting outputLevelChanged fires. Lets island/Island.qml suppress
    // its own volume OSD for edge-originated changes only -- media keys and
    // everything else still go through setVolume()/adjustVolume() with this
    // left false, so they keep their existing OSD feedback untouched.
    property bool edgeOriginated: false

    signal outputLevelChanged(real level, bool muted, string deviceName, bool suppressOsd)
    signal microphoneLevelChanged(real level, bool muted, string deviceName)

    property IpcHandler audioIpc: IpcHandler {
        target: "audio"

        function increment(step: int): string {
            return root.adjustVolume(Math.abs(Number(step)))
        }

        function decrement(step: int): string {
            return root.adjustVolume(-Math.abs(Number(step)))
        }

        function mute(): string {
            if (!root.available)
                return "AUDIO_OUTPUT_UNAVAILABLE"
            root.toggleMute()
            return "AUDIO_MUTE_TOGGLE_SUCCESS"
        }

        function micmute(): string {
            if (!root.microphoneAvailable)
                return "AUDIO_INPUT_UNAVAILABLE"
            root.toggleMicrophoneMute()
            return "MICROPHONE_MUTE_TOGGLE_SUCCESS"
        }

        function setOutput(deviceName: string): string {
            return root.setOutputByName(deviceName)
                ? "AUDIO_OUTPUT_DEVICE_CHANGED"
                : "AUDIO_OUTPUT_DEVICE_NOT_FOUND"
        }

        function setInput(deviceName: string): string {
            return root.setInputByName(deviceName)
                ? "AUDIO_INPUT_DEVICE_CHANGED"
                : "AUDIO_INPUT_DEVICE_NOT_FOUND"
        }
    }

    function streamName(node): string {
        return node?.properties?.["application.name"] || node?.nickname
            || node?.description || node?.name || "Unknown app"
    }

    // Per-app volume, 0..1 (node.audio.volume). Unlike setVolume this never
    // touches the default sink.
    function setStreamVolume(node, level): void {
        if (!node?.audio)
            return
        node.audio.volume = Math.max(0, Math.min(1, level))
    }

    function displayName(node, fallback): string {
        if (!node)
            return fallback
        return node.nickname || node.description || node.name || fallback
    }

    function setVolume(percent): void {
        if (!available)
            return
        const clamped = Math.max(0, Math.min(Config.audio.maxVolumePercent, percent))
        sink.audio.volume = clamped / 100
        if (clamped > 0 && sink.audio.muted)
            sink.audio.muted = false
    }

    // Mirrors setVolume for the default source. Clamped to 100, NOT to
    // maxVolumePercent: over-unity output gain is a loudness choice, but
    // over-unity input gain just clips the microphone before anyone hears it.
    function setMicrophoneVolume(percent): void {
        if (!microphoneAvailable)
            return
        const clamped = Math.max(0, Math.min(100, percent))
        source.audio.volume = clamped / 100
        if (clamped > 0 && source.audio.muted)
            source.audio.muted = false
    }

    // Edge-scroll entry point (edge/VolumeEdge.qml). Identical to setVolume,
    // except it flags the resulting outputLevelChanged as edge-originated so
    // island/Island.qml can skip its own OSD -- the edge gauge is already
    // showing the level, a second popup would be a duplicate.
    function setVolumeFromEdge(percent): void {
        edgeOriginated = true
        setVolume(percent)
    }

    function adjustVolume(delta): string {
        if (!available)
            return "AUDIO_OUTPUT_UNAVAILABLE"
        const numericDelta = Number(delta)
        if (!Number.isFinite(numericDelta) || numericDelta === 0)
            return "AUDIO_INVALID_STEP"
        setVolume(volumePercent + numericDelta)
        return "AUDIO_VOLUME_ADJUST_SUCCESS"
    }

    function toggleMute(): void {
        if (available)
            sink.audio.muted = !sink.audio.muted
    }

    function toggleMicrophoneMute(): void {
        if (microphoneAvailable)
            source.audio.muted = !source.audio.muted
    }

    function setOutputDevice(node): bool {
        if (!node || !outputDevices.includes(node))
            return false
        Pipewire.preferredDefaultAudioSink = node
        return true
    }

    function setInputDevice(node): bool {
        if (!node || !inputDevices.includes(node))
            return false
        Pipewire.preferredDefaultAudioSource = node
        return true
    }

    function setOutputByName(deviceName: string): bool {
        if (!deviceName || deviceName.length === 0)
            return false
        const matchingNodes = outputDevices.filter(node =>
            node.nickname === deviceName || node.description === deviceName
                || node.name === deviceName
        )
        if (matchingNodes.length === 0)
            return false
        return setOutputDevice(matchingNodes[0])
    }

    function setInputByName(deviceName: string): bool {
        if (!deviceName || deviceName.length === 0)
            return false
        const matchingNodes = inputDevices.filter(node =>
            node.nickname === deviceName || node.description === deviceName
                || node.name === deviceName
        )
        if (matchingNodes.length === 0)
            return false
        return setInputDevice(matchingNodes[0])
    }

    function scheduleOutputEvent(): void {
        if (!eventsEnabled || outputEventScheduled)
            return
        outputEventScheduled = true
        Qt.callLater(() => {
            root.outputEventScheduled = false
            const suppress = root.edgeOriginated
            root.edgeOriginated = false
            root.outputLevelChanged(root.volume, root.muted, root.outputName, suppress)
        })
    }

    function scheduleMicrophoneEvent(): void {
        if (!eventsEnabled || microphoneEventScheduled)
            return
        microphoneEventScheduled = true
        Qt.callLater(() => {
            root.microphoneEventScheduled = false
            root.microphoneLevelChanged(root.microphoneVolume, root.microphoneMuted, root.inputName)
        })
    }

    property PwObjectTracker nodeTracker: PwObjectTracker {
        objects: Pipewire.nodes.values.filter(node => node?.audio && !node.isStream)
    }

    property Connections sinkEvents: Connections {
        target: root.sink?.audio ?? null
        function onVolumesChanged(): void {
            root.scheduleOutputEvent()
        }
        function onMutedChanged(): void {
            root.scheduleOutputEvent()
        }
    }

    property Connections sourceEvents: Connections {
        target: root.source?.audio ?? null
        function onVolumesChanged(): void {
            root.scheduleMicrophoneEvent()
        }
        function onMutedChanged(): void {
            root.scheduleMicrophoneEvent()
        }
    }

    property Timer startupGuard: Timer {
        interval: 900
        running: Pipewire.ready
        onTriggered: root.eventsEnabled = true
    }
}
