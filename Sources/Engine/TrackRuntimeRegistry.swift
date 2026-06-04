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
        var activeMonitorMode: AudioInputMonitorMode
        var pendingStartTick: UInt64?
        var pendingStopTick: UInt64?
        var pendingLoopStartTick: UInt64?
        var captureStartTick: UInt64?
        var captureEndTick: UInt64?
        var recordBarLength: Int
        var armedRecordBarLength: Int?
        var recordedLoopID: UUID?
        var recordedLoopBarLength: Int?
        var selectedInputChannel: AudioInputChannel
        var routeState: AudioInputRouteState
        var transientFrameCount: Int
        var liveLevel: AudioInputLevelSnapshot
        var recordingProgress: Double
        var captureWaveformBuckets: [Float]
        var waveformBuckets: [Float]

        init(
            trackID: UUID,
            recordBarLength: Int,
            selectedInputChannel: AudioInputChannel,
            routeState: AudioInputRouteState
        ) {
            self.trackID = trackID
            self.armState = .idle
            self.monitorMode = .input
            self.activeMonitorMode = .input
            self.pendingStartTick = nil
            self.pendingStopTick = nil
            self.pendingLoopStartTick = nil
            self.captureStartTick = nil
            self.captureEndTick = nil
            self.recordBarLength = StepSequenceTrack.normalizedRecordBarLength(recordBarLength)
            self.armedRecordBarLength = nil
            self.recordedLoopID = nil
            self.recordedLoopBarLength = nil
            self.selectedInputChannel = selectedInputChannel
            self.routeState = routeState
            self.transientFrameCount = 0
            self.liveLevel = .silent
            self.recordingProgress = 0
            self.captureWaveformBuckets = []
            self.waveformBuckets = []
        }

        var hasRecordedLoop: Bool {
            recordedLoopID != nil
        }

        var isSilent: Bool {
            routeState == .silentUnavailable ||
                (activeMonitorMode == .loop && !hasRecordedLoop)
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
