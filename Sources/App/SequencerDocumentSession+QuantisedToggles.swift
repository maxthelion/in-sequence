import Foundation

/// Session-level quantise setting for perform-mode toggles (intent-dictation
/// §2): with `.bar`, toggle taps ARM and apply at the next bar boundary;
/// with `.off` they land immediately (exactly today's behaviour). Session
/// UI state like `workspaceMode` — defaults to BAR and is never flushed
/// into the document.
enum PerformQuantise: String, CaseIterable, Identifiable, Sendable {
    case off
    case bar

    var id: String { rawValue }

    var pillLabel: String {
        switch self {
        case .off:
            return "Q: OFF"
        case .bar:
            return "Q: BAR"
        }
    }

    var flipped: PerformQuantise {
        self == .bar ? .off : .bar
    }
}

extension SequencerDocumentSession {
    /// True when a perform toggle tap should arm for the bar boundary
    /// instead of landing immediately. Requires the transport: with the
    /// clock stopped there is no boundary to wait for, so taps fall back to
    /// the immediate path (the step-order toggle's fallback shape).
    var isQuantisedPerformToggleArmingActive: Bool {
        workspaceMode == .perform && performQuantise == .bar && engineController.isRunning
    }

    func installQuantisedToggleCommittedHandler() {
        engineController.quantisedToggleCommittedHandler = { [weak self] changes in
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self?.applyCommittedQuantisedToggles(changes)
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.applyCommittedQuantisedToggles(changes)
                }
            }
        }
    }

    /// Mute tap in perform mode with Q:BAR — arms one quantised mute toggle
    /// per recipient (tap-while-armed cancels that track's arm). The target
    /// value is captured at arm time from the overlay-applied basis phrase,
    /// the same capture-at-arm shape as the step-order toggle.
    func toggleQuantisedMute(
        trackIDs: [UUID],
        basisPhrase: PhraseModel,
        layer: PhraseLayerDefinition,
        stepIndex: Int
    ) {
        for trackID in trackIDs {
            let currentValue = basisPhrase.resolvedValue(for: layer, trackID: trackID, stepIndex: stepIndex)
            let targetMuted: Bool
            if case let .bool(isMuted) = currentValue.normalized(for: layer) {
                targetMuted = !isMuted
            } else {
                targetMuted = true
            }
            engineController.armQuantisedToggle(
                .mute(trackID: trackID, muted: targetMuted, basisPhraseID: basisPhrase.id)
            )
        }
    }

    /// Fill's third gesture (rytm-study §5): a plain tap with Q on arms a
    /// next-cycle cue — fill plays the next bar, then auto-returns. Group
    /// semantics match the latch toggle: if every recipient is already
    /// armed the tap cancels them all, otherwise it arms the set.
    func toggleQuantisedFillCue(trackIDs: [UUID]) {
        let allArmed = trackIDs.allSatisfy { engineController.hasQuantisedPendingFillCue(for: $0) }
        for trackID in trackIDs {
            let isArmed = engineController.hasQuantisedPendingFillCue(for: trackID)
            // Arm the un-armed (or cancel everything when all were armed):
            // armOrCancel flips per key, so skip tracks already in the
            // desired state.
            if allArmed || !isArmed {
                engineController.armQuantisedToggle(.fillCue(trackID: trackID))
            }
        }
    }

    /// Boundary commit mirror (installed as the engine's committed handler):
    /// the engine already applied the changes on the tick path; this stages
    /// the document record for mute changes through the phrase perform
    /// overlay — identical to what an immediate tap would have staged — and
    /// then retires the engine's live overrides. Fill cues are runtime-only
    /// and need no document record.
    func applyCommittedQuantisedToggles(_ changes: [QuantisedToggleChange]) {
        guard let muteLayerID = TrackPerformLayerMode.mute.phraseLayerID else {
            return
        }

        var committedMuteTrackIDs: [UUID] = []
        for change in changes {
            guard case let .mute(trackID, muted, basisPhraseID) = change else {
                continue
            }
            stagePhrasePerformCell(
                .single(.bool(muted)),
                layerID: muteLayerID,
                trackIDs: [trackID],
                basisPhraseID: basisPhraseID
            )
            committedMuteTrackIDs.append(trackID)
        }

        guard !committedMuteTrackIDs.isEmpty else {
            return
        }
        // The staging above published a snapshot that encodes the mutes;
        // installed synchronously, so the overrides can retire without a
        // window where neither source carries the value.
        engineController.confirmQuantisedMuteApplied(trackIDs: committedMuteTrackIDs)
    }
}
