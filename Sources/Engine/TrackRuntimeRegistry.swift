import Foundation

extension EngineController {
    final class TrackRuntimeRegistry {
        var generatorIDsByTrackID: [UUID: BlockID] = [:]
        var midiOutBlocksByTrackID: [UUID: MidiOut] = [:]
        var audioTrackRuntimes: [UUID: AudioTrackRuntime] = [:]
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
