import Foundation

extension EngineController {
    enum AudioInputArmState: Equatable, Sendable {
        case idle
        case armed
        case recording
        case hasLoop
    }

    enum AudioInputMonitorMode: Equatable, Sendable {
        case input
        case loop
    }

    enum AudioInputRouteState: Equatable, Sendable {
        case available
        case silentUnavailable
    }

    struct AudioInputTrackRuntime: Equatable, Sendable {
        let trackID: UUID
        var armState: AudioInputArmState
        var monitorMode: AudioInputMonitorMode
        var pendingStartTick: UInt64?
        var selectedInputChannel: AudioInputChannel
        var routeState: AudioInputRouteState
        var transientFrameCount: Int
        var waveformBuckets: [Float]

        init(
            trackID: UUID,
            selectedInputChannel: AudioInputChannel,
            routeState: AudioInputRouteState
        ) {
            self.trackID = trackID
            self.armState = .idle
            self.monitorMode = .input
            self.pendingStartTick = nil
            self.selectedInputChannel = selectedInputChannel
            self.routeState = routeState
            self.transientFrameCount = 0
            self.waveformBuckets = []
        }

        var isSilent: Bool {
            routeState == .silentUnavailable ||
                (monitorMode == .loop && armState != .hasLoop)
        }
    }

    final class TrackRuntimeRegistry {
        var generatorIDsByTrackID: [UUID: BlockID] = [:]
        var midiOutBlocksByTrackID: [UUID: MidiOut] = [:]
        var audioTrackRuntimes: [UUID: AudioTrackRuntime] = [:]
        var audioInputRuntimes: [UUID: AudioInputTrackRuntime] = [:]
        var audioOutputsByTrackID: [UUID: TrackPlaybackSink] = [:]
        var audioOutputKeysByTrackID: [UUID: AudioOutputKey] = [:]
        var effectiveMutedTrackIDs: Set<UUID> = []
        var effectiveMutedBusIDs: Set<UUID> = []
        var lastDestinationByOutputKey: [AudioOutputKey: Destination] = [:]
        var liveSampleTrackIDs: Set<UUID> = []
        var pipelineShape: [PipelineEntry] = []

        func resetSinks() {
            audioOutputsByTrackID = [:]
            audioOutputKeysByTrackID = [:]
            lastDestinationByOutputKey = [:]
            audioTrackRuntimes = [:]
            audioInputRuntimes = [:]
            liveSampleTrackIDs = []
        }

        func installPipeline(
            generatorIDs: [UUID: BlockID],
            midiOutBlocks: [UUID: MidiOut],
            audioRuntimes: [UUID: AudioTrackRuntime],
            pipelineShape: [PipelineEntry]
        ) {
            generatorIDsByTrackID = generatorIDs
            midiOutBlocksByTrackID = midiOutBlocks
            audioTrackRuntimes = audioRuntimes
            self.pipelineShape = pipelineShape
        }

        func installAudioOutputs(
            outputs: [UUID: TrackPlaybackSink],
            outputKeys: [UUID: AudioOutputKey],
            destinationsByOutputKey: [AudioOutputKey: Destination],
            audioRuntimes: [UUID: AudioTrackRuntime]
        ) {
            audioOutputsByTrackID = outputs
            audioOutputKeysByTrackID = outputKeys
            lastDestinationByOutputKey = destinationsByOutputKey
            audioTrackRuntimes = audioRuntimes
        }

        func installMuteState(_ muteState: EffectiveMixerMuteState) {
            effectiveMutedTrackIDs = muteState.mutedTrackIDs
            effectiveMutedBusIDs = muteState.mutedBusIDs
        }
    }
}
