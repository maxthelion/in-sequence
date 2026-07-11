import Foundation

/// Status/presentation summaries for `EngineController` — display-oriented
/// computed state only. Mechanically extracted from EngineController.swift
/// (engine carve-up stage: status/presentation); no behavior change.
extension EngineController {
    var statusSummary: String {
        // `currentDocumentModel` is @ObservationIgnored (mixer render-livelock
        // fix), so read the observed structural-change trigger here to register
        // SwiftUI observation: the status string re-evaluates when the document
        // structure (destination/port/mute) changes, but NOT on per-drag mixer
        // moves (which never bump this revision).
        _ = documentModelUIRevision
        guard canStart else {
            return "Engine unavailable"
        }

        let selectedTrack = currentDocumentModel.selectedTrack
        if selectedTrack.trackType == .audioInput {
            return audioInputStatusSummary(for: selectedTrack)
        }
        let (destination, _) = effectiveDestination(for: selectedTrack.id)
        switch destination {
        case .midi:
            if selectedTrack.mix.isMuted {
                return "MIDI output muted"
            }
            guard case let .midi(port, _, _) = destination,
                  let port
            else {
                return "Playing without MIDI output"
            }
            return "Output: \(port.displayName)"
        case .auInstrument:
            let host = withStateLock { trackRuntime.audioOutputsByTrackID[selectedTrack.id] }
            guard let host else {
                return "Audio instrument unavailable"
            }
            if let failure = host.loadFailure {
                return "Audio unavailable: \(failure.instrumentName) (\(failure.domain) \(failure.code))"
            }
            return host.isAvailable
                ? "Audio: \(host.displayName) via Main Mixer\(selectedTrack.mix.isMuted ? " (Muted)" : "")"
                : "Audio instrument unavailable"
        case .internalSampler:
            return "Internal sampler pending"
        case let .sample(sampleID, _):
            return sampleStatusSummary(sampleID: sampleID, isMuted: selectedTrack.mix.isMuted)
        case let .slicer(sliceSetID, _):
            let sliceSet = tickState.currentPlaybackSnapshot().sliceSet(id: sliceSetID)
            if let sampleID = sliceSet?.sampleID {
                switch sampleAssetCache.readiness(sampleID: sampleID) {
                case .ready:
                    break
                case .loading:
                    return "Slicer playback pending"
                case .failed:
                    return "Slicer sample failed to load"
                case .stale:
                    return "Slicer sample stale, reload pending"
                case .missing:
                    return "Slicer playback pending"
                }
            }
            let count = sliceSet?.displaySliceCount ?? 0
            return count > 0 ? "Slicer • \(count) slices" : "Slicer • Choose a loop"
        case .inheritGroup, .none:
            return "No default output"
        }
    }

    /// Audio-input tracks have no note destination, so the generic summary
    /// used to claim "No default output"; describe the monitor routing
    /// instead, in the panel's Live/Buffer vocabulary.
    private func audioInputStatusSummary(for track: StepSequenceTrack) -> String {
        guard let runtime = audioInputRuntime(for: track.id) else {
            return "Audio In • Connecting"
        }
        if runtime.routeState == .silentUnavailable {
            return "Audio In • No input device"
        }
        let muted = track.mix.isMuted ? " (Muted)" : ""
        switch runtime.armState {
        case .armed:
            return "Audio In • Armed, records at next bar\(muted)"
        case .recording:
            let bars = runtime.armedRecordBarLength ?? runtime.recordBarLength
            return "Audio In • Recording \(bars) bar\(bars == 1 ? "" : "s")\(muted)"
        case .idle, .hasLoop:
            break
        }
        switch runtime.activeMonitorMode {
        case .input:
            return "Audio In • Live monitor\(muted)"
        case .loop:
            guard let bars = runtime.recordedLoopBarLength else {
                return "Audio In • Buffer\(muted)"
            }
            return "Audio In • Buffer (\(bars) bar\(bars == 1 ? "" : "s"))\(muted)"
        }
    }

    private func sampleStatusSummary(sampleID: UUID, isMuted: Bool) -> String {
        guard let sample = sampleLibrary.sample(id: sampleID) else {
            return "Sample missing"
        }
        switch sampleAssetCache.readiness(sampleID: sampleID) {
        case .ready:
            break
        case .loading:
            return "Sample playback pending"
        case .failed:
            return "Sample failed to load"
        case .stale:
            return "Sample stale, reload pending"
        case .missing:
            return "Sample playback pending"
        }
        return "Sample: \(sample.name) via Main Mixer\(isMuted ? " (Muted)" : "")"
    }
}
