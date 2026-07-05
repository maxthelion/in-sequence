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
        stepIndex: Int,
        lengthBars: Int? = nil
    ) {
        for trackID in trackIDs {
            let currentValue = basisPhrase.resolvedValue(for: layer, trackID: trackID, stepIndex: stepIndex)
            let targetMuted: Bool
            if case let .bool(isMuted) = currentValue.normalized(for: layer) {
                targetMuted = !isMuted
            } else {
                targetMuted = true
            }
            let change: QuantisedToggleChange
            if let lengthBars {
                change = .lengthLimitedMute(
                    trackID: trackID,
                    muted: targetMuted,
                    basisPhraseID: basisPhrase.id,
                    lengthBars: max(1, lengthBars),
                    startTick: nil
                )
            } else {
                change = .mute(trackID: trackID, muted: targetMuted, basisPhraseID: basisPhrase.id)
            }
            engineController.armQuantisedToggle(change)
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

    /// Fill flag in phrase Perform with Q:BAR. Unlike the runtime-only fill
    /// cue, this is a phrase-layer change: commit at the boundary, stage the
    /// overlay record, and make it capturable with the phrase.
    func toggleQuantisedFillFlag(
        trackIDs: [UUID],
        basisPhrase: PhraseModel,
        layer: PhraseLayerDefinition,
        stepIndex: Int,
        lengthBars: Int? = nil
    ) {
        for trackID in trackIDs {
            let currentValue = basisPhrase.resolvedValue(for: layer, trackID: trackID, stepIndex: stepIndex)
            let targetEnabled: Bool
            if case let .bool(isEnabled) = currentValue.normalized(for: layer) {
                targetEnabled = !isEnabled
            } else {
                targetEnabled = true
            }
            engineController.armQuantisedToggle(.fillFlag(
                trackID: trackID,
                enabled: targetEnabled,
                basisPhraseID: basisPhrase.id,
                lengthBars: lengthBars.map { max(1, $0) },
                startTick: nil
            ))
        }
    }

    /// Pattern in phrase Perform with Q:BAR. This is a phrase-layer change
    /// like Mute/Fill Flag: commit at the boundary, stage the overlay record,
    /// and keep the boundary tick honest with an engine-side slot override.
    func toggleQuantisedPatternIndex(
        trackIDs: [UUID],
        basisPhrase: PhraseModel,
        layer: PhraseLayerDefinition,
        stepIndex: Int,
        lengthBars: Int? = nil
    ) {
        for trackID in trackIDs {
            let currentValue = basisPhrase.resolvedValue(for: layer, trackID: trackID, stepIndex: stepIndex)
            let currentIndex: Int
            if case let .index(index) = currentValue.normalized(for: layer) {
                currentIndex = index
            } else {
                currentIndex = 0
            }
            engineController.armQuantisedToggle(.pattern(
                trackID: trackID,
                slotIndex: (currentIndex + 1) % TrackPatternBank.slotCount,
                basisPhraseID: basisPhrase.id,
                lengthBars: lengthBars.map { max(1, $0) },
                startTick: nil
            ))
        }
    }

    /// Explicit pattern-slot selection in phrase Perform with Q:BAR. Mini
    /// cells use this instead of the cycling helper so P4 arms exactly P4
    /// while still sharing the boundary scheduler and overlay staging path.
    func selectQuantisedPatternIndex(
        slotIndex: Int,
        trackIDs: [UUID],
        basisPhrase: PhraseModel,
        lengthBars: Int? = nil
    ) {
        let clampedSlotIndex = min(max(slotIndex, 0), TrackPatternBank.slotCount - 1)
        for trackID in trackIDs {
            engineController.armQuantisedToggle(.pattern(
                trackID: trackID,
                slotIndex: clampedSlotIndex,
                basisPhraseID: basisPhrase.id,
                lengthBars: lengthBars.map { max(1, $0) },
                startTick: nil
            ))
        }
    }

    /// Boundary commit mirror (installed as the engine's committed handler):
    /// the engine already applied the changes on the tick path; this stages
    /// the document record for mute changes through the phrase perform
    /// overlay — identical to what an immediate tap would have staged — and
    /// then retires the engine's live overrides. Fill cues are runtime-only
    /// and need no document record.
    func applyCommittedQuantisedToggles(_ changes: [QuantisedToggleChange]) {
        guard let muteLayerID = TrackPerformLayerMode.mute.phraseLayerID,
              let fillLayerID = TrackPerformLayerMode.fill.phraseLayerID,
              let patternLayerID = TrackPerformLayerMode.pattern.phraseLayerID
        else {
            return
        }

        var committedMuteTrackIDs: [UUID] = []
        var committedFillTrackIDs: [UUID] = []
        var committedPatternTrackIDs: [UUID] = []
        for change in changes {
            switch change {
            case let .mute(trackID, muted, basisPhraseID):
                stagePhrasePerformCell(
                    .single(.bool(muted)),
                    layerID: muteLayerID,
                    trackIDs: [trackID],
                    basisPhraseID: basisPhraseID
                )
                committedMuteTrackIDs.append(trackID)
            case let .lengthLimitedMute(trackID, muted, basisPhraseID, lengthBars, startTick):
                stageLengthLimitedMute(
                    muted: muted,
                    trackID: trackID,
                    basisPhraseID: basisPhraseID,
                    layerID: muteLayerID,
                    lengthBars: lengthBars,
                    startTick: startTick
                )
                committedMuteTrackIDs.append(trackID)
            case let .fillFlag(trackID, enabled, basisPhraseID, lengthBars, startTick):
                if let lengthBars {
                    stageLengthLimitedBooleanCell(
                        value: enabled,
                        trackID: trackID,
                        basisPhraseID: basisPhraseID,
                        layerID: fillLayerID,
                        lengthBars: lengthBars,
                        startTick: startTick
                    )
                } else {
                    stagePhrasePerformCell(
                        .single(.bool(enabled)),
                        layerID: fillLayerID,
                        trackIDs: [trackID],
                        basisPhraseID: basisPhraseID
                    )
                }
                committedFillTrackIDs.append(trackID)
            case let .pattern(trackID, slotIndex, basisPhraseID, lengthBars, startTick):
                if let lengthBars {
                    stageLengthLimitedCell(
                        value: .index(slotIndex),
                        trackID: trackID,
                        basisPhraseID: basisPhraseID,
                        layerID: patternLayerID,
                        lengthBars: lengthBars,
                        startTick: startTick
                    )
                } else {
                    stagePhrasePerformCell(
                        .single(.index(slotIndex)),
                        layerID: patternLayerID,
                        trackIDs: [trackID],
                        basisPhraseID: basisPhraseID
                    )
                }
                committedPatternTrackIDs.append(trackID)
            case .fillCue:
                continue
            }
        }

        if !committedMuteTrackIDs.isEmpty {
            // The staging above published a snapshot that encodes the mutes;
            // installed synchronously, so the overrides can retire without a
            // window where neither source carries the value.
            engineController.confirmQuantisedMuteApplied(trackIDs: committedMuteTrackIDs)
        }
        if !committedFillTrackIDs.isEmpty {
            engineController.confirmQuantisedFillFlagApplied(trackIDs: committedFillTrackIDs)
        }
        if !committedPatternTrackIDs.isEmpty {
            engineController.confirmQuantisedPatternApplied(trackIDs: committedPatternTrackIDs)
        }
    }

    private func stageLengthLimitedMute(
        muted: Bool,
        trackID: UUID,
        basisPhraseID: UUID,
        layerID: String,
        lengthBars: Int,
        startTick: UInt64?
    ) {
        stageLengthLimitedBooleanCell(
            value: muted,
            trackID: trackID,
            basisPhraseID: basisPhraseID,
            layerID: layerID,
            lengthBars: lengthBars,
            startTick: startTick
        )
    }

    private func stageLengthLimitedBooleanCell(
        value: Bool,
        trackID: UUID,
        basisPhraseID: UUID,
        layerID: String,
        lengthBars: Int,
        startTick: UInt64?
    ) {
        stageLengthLimitedCell(
            value: .bool(value),
            trackID: trackID,
            basisPhraseID: basisPhraseID,
            layerID: layerID,
            lengthBars: lengthBars,
            startTick: startTick
        )
    }

    private func stageLengthLimitedCell(
        value: PhraseCellValue,
        trackID: UUID,
        basisPhraseID: UUID,
        layerID: String,
        lengthBars: Int,
        startTick: UInt64?
    ) {
        guard let phrase = store.phrases.first(where: { $0.id == basisPhraseID }),
              let layer = store.layer(id: layerID)
        else {
            stagePhrasePerformCell(
                .single(value),
                layerID: layerID,
                trackIDs: [trackID],
                basisPhraseID: basisPhraseID
            )
            return
        }

        let displayedPhrase = phraseWithPerformOverlay(phrase)
        let startTick = startTick ?? engineController.transportTickIndex
        let startBarIndex = PhrasePlayhead(
            phrase: displayedPhrase,
            transportTickIndex: startTick
        ).barIndex
        var barValues = (0..<displayedPhrase.lengthBars).map { barIndex in
            displayedPhrase.resolvedValue(
                for: layer,
                trackID: trackID,
                stepIndex: barIndex * displayedPhrase.stepsPerBar
            )
            .normalized(for: layer)
        }

        let endBarIndex = min(displayedPhrase.lengthBars, startBarIndex + max(1, lengthBars))
        guard startBarIndex < endBarIndex else {
            return
        }
        for barIndex in startBarIndex..<endBarIndex {
            barValues[barIndex] = value.normalized(for: layer)
        }

        stagePhrasePerformCell(
            .bars(barValues),
            layerID: layerID,
            trackIDs: [trackID],
            basisPhraseID: basisPhraseID
        )
    }
}
