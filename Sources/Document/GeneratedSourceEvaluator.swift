import Foundation

/// One realized source hit used by the density transform: the step it fires
/// on plus a representative pitch/velocity so ghost triggers can be
/// velocity-scaled from their neighbours and repeat the neighbouring pitch
/// (repeat-last for clips; for generators the neighbour's pitch was realized
/// through the pitch stage's pool policy, so a ghost repeating it stays a
/// pool-policy note).
struct DensitySourceHit: Equatable, Sendable {
    let step: Int
    let pitch: Int
    let velocity: Int
    let voiceTag: VoiceTag?
}

enum GeneratedSourceEvaluator {
    static func cycleLength(
        for params: GeneratorParams,
        clipChoices: [ClipPoolEntry]
    ) -> Int {
        cycleLength(for: params.generatedSourcePipeline, clipChoices: clipChoices)
    }

    static func cycleLength(
        for pipeline: GeneratedSourcePipeline,
        clipChoices: [ClipPoolEntry]
    ) -> Int {
        switch pipeline.content {
        case .melodic:
            guard let trigger = pipeline.trigger else { return 1 }
            return max(triggerCycleLength(trigger, clipChoices: clipChoices), 1)
        case let .progressionChords(params):
            return max(params.normalized.lengthSteps, 1)
        case let .drum(triggers, _):
            let maxLength = triggers.values.map { triggerCycleLength($0, clipChoices: clipChoices) }.max() ?? 1
            return max(maxLength, 1)
        case .slice:
            guard let trigger = pipeline.trigger else { return 1 }
            return max(triggerCycleLength(trigger, clipChoices: clipChoices), 1)
        case .template:
            return 1
        }
    }

    static func evaluateStep<R: RandomNumberGenerator>(
        for params: GeneratorParams,
        stepIndex: Int,
        clipChoices: [ClipPoolEntry],
        chordContext: Chord?,
        state: inout GeneratedSourceEvaluationState,
        stateScope: GeneratedSourceEvaluationScope = .primary,
        rng: inout R
    ) -> [GeneratedNote] {
        let sourceNotes = evaluateSourceStep(
            for: params,
            stepIndex: stepIndex,
            clipChoices: clipChoices,
            rng: &rng
        )

        return processSourceNotes(
            sourceNotes,
            through: params,
            stepIndex: stepIndex,
            clipChoices: clipChoices,
            chordContext: chordContext,
            state: &state,
            stateScope: stateScope,
            rng: &rng
        )
    }

    static func evaluateSourceStep<R: RandomNumberGenerator>(
        for params: GeneratorParams,
        stepIndex: Int,
        clipChoices: [ClipPoolEntry],
        rng: inout R
    ) -> [GeneratedNote] {
        switch params {
        case let .mono(trigger, _, shape):
            let seeds = emittedSeeds(
                from: trigger,
                stepIndex: stepIndex,
                totalSteps: cycleLength(for: params, clipChoices: clipChoices),
                clipChoices: clipChoices,
                rng: &rng,
                voiceTag: nil
            )

            return seeds.map { seed in
                GeneratedNote(
                    pitch: clampMIDI(seed.pitch),
                    velocity: clampMIDI(shape.velocity),
                    length: max(1, shape.gateLength),
                    voiceTag: seed.voiceTag
                )
            }

        case let .poly(trigger, _, shape):
            let seeds = emittedSeeds(
                from: trigger,
                stepIndex: stepIndex,
                totalSteps: cycleLength(for: params, clipChoices: clipChoices),
                clipChoices: clipChoices,
                rng: &rng,
                voiceTag: nil
            )

            return seeds.map { seed in
                GeneratedNote(
                    pitch: clampMIDI(seed.pitch),
                    velocity: clampMIDI(shape.velocity),
                    length: max(1, shape.gateLength),
                    voiceTag: seed.voiceTag
                )
            }

        case let .progressionChords(params):
            return params.generatedNotes(at: stepIndex)

        case let .drum(triggers, shape):
            let totalSteps = cycleLength(for: params, clipChoices: clipChoices)
            return triggers.keys.sorted().flatMap { voiceTag in
                guard let trigger = triggers[voiceTag] else {
                    return [GeneratedNote]()
                }

                let seeds = emittedSeeds(
                    from: trigger,
                    stepIndex: stepIndex,
                    totalSteps: totalSteps,
                    clipChoices: clipChoices,
                    rng: &rng,
                    voiceTag: voiceTag
                )
                return seeds.map { seed in
                    GeneratedNote(
                        pitch: clampMIDI(seed.pitch),
                        velocity: clampMIDI(shape.velocity),
                        length: max(1, shape.gateLength),
                        voiceTag: seed.voiceTag
                    )
                }
            }

        case let .slice(trigger, sliceIndexes):
            let seeds = emittedSeeds(
                from: trigger,
                stepIndex: stepIndex,
                totalSteps: cycleLength(for: params, clipChoices: clipChoices),
                clipChoices: clipChoices,
                rng: &rng,
                voiceTag: nil
            )
            let resolvedIndexes = sliceIndexes.isEmpty ? [0] : sliceIndexes
            return seeds.enumerated().map { index, _ in
                let sliceIndex = resolvedIndexes[(stepIndex + index) % resolvedIndexes.count]
                return GeneratedNote(
                    pitch: 60,
                    velocity: clampMIDI(NoteShape.default.velocity),
                    length: max(1, NoteShape.default.gateLength),
                    voiceTag: sliceVoiceTag(sliceIndex)
                )
            }

        case .template:
            return []
        }
    }

    static func evaluateStep<R: RandomNumberGenerator>(
        for pipeline: GeneratedSourcePipeline,
        stepIndex: Int,
        clipChoices: [ClipPoolEntry],
        chordContext: Chord?,
        state: inout GeneratedSourceEvaluationState,
        stateScope: GeneratedSourceEvaluationScope = .primary,
        rng: inout R
    ) -> [GeneratedNote] {
        switch pipeline.content {
        case let .melodic(pitches, shape):
            guard let trigger = pipeline.trigger else {
                return []
            }
            let seeds = emittedSeeds(
                from: trigger,
                stepIndex: stepIndex,
                totalSteps: cycleLength(for: pipeline, clipChoices: clipChoices),
                clipChoices: clipChoices,
                rng: &rng,
                voiceTag: nil
            )

            return seeds.flatMap { seed in
                pitches.enumerated().flatMap { laneIndex, pitch in
                    evaluatedPitchStage(
                        pitch,
                        seed: seed,
                        stepIndex: stepIndex,
                        clipChoices: clipChoices,
                        chordContext: chordContext,
                        laneIndex: laneIndex,
                        shape: shape,
                        state: &state,
                        stateScope: stateScope,
                        rng: &rng
                    )
                }
            }

        case let .progressionChords(params):
            return params.generatedNotes(at: stepIndex)

        case let .drum(triggers, shape):
            let totalSteps = cycleLength(for: pipeline, clipChoices: clipChoices)
            return triggers.keys.sorted().flatMap { voiceTag in
                guard let trigger = triggers[voiceTag] else {
                    return [GeneratedNote]()
                }

                let seeds = emittedSeeds(
                    from: trigger,
                    stepIndex: stepIndex,
                    totalSteps: totalSteps,
                    clipChoices: clipChoices,
                    rng: &rng,
                    voiceTag: voiceTag
                )
                return seeds.map { seed in
                    GeneratedNote(
                        pitch: clampMIDI(seed.pitch),
                        velocity: clampMIDI(shape.velocity),
                        length: max(1, shape.gateLength),
                        voiceTag: seed.voiceTag
                    )
                }
            }

        case .template:
            return []

        case let .slice(sliceIndexes):
            guard let trigger = pipeline.trigger else {
                return []
            }
            let seeds = emittedSeeds(
                from: trigger,
                stepIndex: stepIndex,
                totalSteps: cycleLength(for: pipeline, clipChoices: clipChoices),
                clipChoices: clipChoices,
                rng: &rng,
                voiceTag: nil
            )
            let resolvedIndexes = sliceIndexes.isEmpty ? [0] : sliceIndexes
            return seeds.enumerated().map { index, _ in
                let sliceIndex = resolvedIndexes[(stepIndex + index) % resolvedIndexes.count]
                return GeneratedNote(
                    pitch: 60,
                    velocity: clampMIDI(NoteShape.default.velocity),
                    length: max(1, NoteShape.default.gateLength),
                    voiceTag: sliceVoiceTag(sliceIndex)
                )
            }
        }
    }

    static func previewNotes(
        for params: GeneratorParams,
        clipChoices: [ClipPoolEntry],
        count: Int = 16,
        chordContext: Chord? = nil
    ) -> [[GeneratedNote]] {
        previewNotes(
            for: params.generatedSourcePipeline,
            clipChoices: clipChoices,
            count: count,
            chordContext: chordContext
        )
    }

    static func previewNotes(
        for pipeline: GeneratedSourcePipeline,
        clipChoices: [ClipPoolEntry],
        count: Int = 16,
        chordContext: Chord? = nil
    ) -> [[GeneratedNote]] {
        var rng = PreviewRNG()
        var state = GeneratedSourceEvaluationState()
        return (0..<count).map { stepIndex in
            evaluateStep(
                for: pipeline,
                stepIndex: stepIndex,
                clipChoices: clipChoices,
                chordContext: chordContext,
                state: &state,
                rng: &rng
            )
        }
    }

    static func clipPitchPool(for clip: ClipPoolEntry) -> [Int] {
        clip.pitchPool
    }

    static func clipStepPatternFires(
        for clip: ClipPoolEntry,
        stepIndex: Int
    ) -> Bool {
        switch clip.content {
        case let .noteGrid(lengthSteps, steps):
            guard !steps.isEmpty else { return false }
            let normalizedStep = positiveModulo(stepIndex, max(lengthSteps, 1))
            return !steps[normalizedStep].isEmpty
        case let .sliceTriggers(stepPattern, _, _, _):
            guard !stepPattern.isEmpty else { return false }
            return stepPattern[stepIndex % stepPattern.count]
        }
    }

    // MARK: - Density transform (WS5)

    /// Source-hit profile for a clip: every firing step with a representative
    /// note (main lane first, fill fallback). Deterministic — reads the clip
    /// content directly, no RNG (chance-gated lanes count as hits so the
    /// candidate map is loop-stable).
    static func densitySourceHits(
        for clip: ClipPoolEntry,
        stepCount: Int
    ) -> [DensitySourceHit] {
        let count = max(stepCount, 1)
        return (0..<count).compactMap { step in
            guard clipStepPatternFires(for: clip, stepIndex: step) else {
                return nil
            }
            if let note = clipStepRepresentativeNote(for: clip, stepIndex: step) {
                return DensitySourceHit(step: step, pitch: note.pitch, velocity: note.velocity, voiceTag: note.voiceTag)
            }
            return DensitySourceHit(
                step: step,
                pitch: clip.pitchPool.first ?? 60,
                velocity: clampMIDI(NoteShape.default.velocity),
                voiceTag: nil
            )
        }
    }

    /// Source-hit profile for a generator: deterministic full evaluation
    /// (trigger + pitch stage) under the fixed preview seed, so the ghost's
    /// neighbour pitch is a realized pool-policy note and the profile is
    /// identical every loop.
    static func densitySourceHits(
        for params: GeneratorParams,
        stepCount: Int,
        clipChoices: [ClipPoolEntry]
    ) -> [DensitySourceHit] {
        let count = max(stepCount, 1)
        let cycle = max(cycleLength(for: params, clipChoices: clipChoices), 1)
        var rng = PreviewRNG()
        var state = GeneratedSourceEvaluationState()
        return (0..<count).compactMap { step in
            let notes = evaluateStep(
                for: params,
                stepIndex: step % cycle,
                clipChoices: clipChoices,
                chordContext: nil,
                state: &state,
                rng: &rng
            )
            guard let note = notes.first else {
                return nil
            }
            return DensitySourceHit(step: step, pitch: note.pitch, velocity: note.velocity, voiceTag: note.voiceTag)
        }
    }

    /// The DENSITY transform stage (synthesis §4): density 0..1 adds ghost
    /// triggers at candidate positions derived from the existing hits,
    /// respecting the source's CLUSTER character. Inclusion is decided by
    /// `hash(patternID, step) < density` — deterministic per position, so the
    /// ghost set is loop-stable and strictly grows as density sweeps up
    /// (monotonic: a step admitted at 0.5 stays admitted at 0.7). Zero RNG.
    ///
    /// Ghosts are velocity-scaled from their neighbours (mean of the nearest
    /// preceding/following hit velocities, scaled down) and repeat the nearest
    /// preceding hit's pitch (repeat-last for clips; a realized pool-policy
    /// note for generators — see `DensitySourceHit`).
    static func applyingDensityTransform(
        to notes: [GeneratedNote],
        stepIndex: Int,
        stepCount: Int,
        patternID: UUID,
        density: Double,
        cluster: Double,
        sourceHits: [DensitySourceHit],
        fallbackPitch: Int
    ) -> [GeneratedNote] {
        let normalizedDensity = min(max(density, 0), 1)
        guard normalizedDensity > 0 else {
            return notes
        }
        let count = max(stepCount, 1)
        let normalizedStep = positiveModulo(stepIndex, count)
        var hitsByStep: [Int: DensitySourceHit] = [:]
        for hit in sourceHits {
            hitsByStep[positiveModulo(hit.step, count)] = hit
        }
        let normalizedHits = Set(hitsByStep.keys)
        guard !normalizedHits.isEmpty, !normalizedHits.contains(normalizedStep) else {
            return notes
        }
        guard densityCandidateIsEligible(
            step: normalizedStep,
            stepCount: count,
            hitSteps: normalizedHits,
            cluster: cluster
        ) else {
            return notes
        }
        guard stableDensityFraction(patternID: patternID, step: normalizedStep) < normalizedDensity else {
            return notes
        }

        let preceding = nearestHit(from: normalizedStep, in: hitsByStep, stepCount: count, direction: -1)
        let following = nearestHit(from: normalizedStep, in: hitsByStep, stepCount: count, direction: 1)
        let neighbourVelocities = [preceding, following].compactMap { $0?.velocity }
        let neighbourMean = neighbourVelocities.isEmpty
            ? 96
            : neighbourVelocities.reduce(0, +) / neighbourVelocities.count
        let ghostVelocity = min(max(Int((Double(neighbourMean) * 0.65).rounded()), 1), 127)
        let ghost = GeneratedNote(
            pitch: clampMIDI(preceding?.pitch ?? following?.pitch ?? fallbackPitch),
            velocity: ghostVelocity,
            length: 1,
            voiceTag: preceding?.voiceTag ?? following?.voiceTag
        )
        return notes + [ghost]
    }

    /// First note of the clip step's main lane (fill fallback), read straight
    /// from the normalized content — the deterministic "repeat-last" pitch and
    /// neighbour-velocity source for clip ghosts.
    private static func clipStepRepresentativeNote(
        for clip: ClipPoolEntry,
        stepIndex: Int
    ) -> GeneratedNote? {
        switch clip.content.normalized {
        case let .noteGrid(lengthSteps, steps):
            guard !steps.isEmpty else { return nil }
            let normalizedStep = positiveModulo(stepIndex, max(lengthSteps, 1))
            let step = steps[normalizedStep]
            guard let note = step.main?.notes.first ?? step.fill?.notes.first else {
                return nil
            }
            return GeneratedNote(
                pitch: clampMIDI(note.pitch),
                velocity: clampMIDI(note.velocity),
                length: max(1, note.lengthSteps),
                voiceTag: nil
            )
        case .sliceTriggers:
            return GeneratedNote(
                pitch: 60,
                velocity: clampMIDI(NoteShape.default.velocity),
                length: 1,
                voiceTag: nil
            )
        }
    }

    static func resolveClipStep<R: RandomNumberGenerator>(
        for clip: ClipPoolEntry,
        stepIndex: Int,
        fillEnabled: Bool,
        rng: inout R
    ) -> [GeneratedNote] {
        switch clip.content.normalized {
        case let .noteGrid(lengthSteps, steps):
            guard !steps.isEmpty else { return [] }
            let normalizedStep = positiveModulo(stepIndex, max(lengthSteps, 1))
            let step = steps[normalizedStep]
            let resolvedLane: ClipLane?
            if fillEnabled,
               let fill = step.fill,
               laneFires(fill, rng: &rng)
            {
                resolvedLane = fill
            } else if let main = step.main,
                      laneFires(main, rng: &rng)
            {
                resolvedLane = main
            } else {
                resolvedLane = nil
            }

            return resolvedLane?.notes.map { note in
                GeneratedNote(
                    pitch: clampMIDI(note.pitch),
                    velocity: clampMIDI(note.velocity),
                    length: max(1, note.lengthSteps),
                    voiceTag: nil
                )
            } ?? []

        case let .sliceTriggers(stepPattern, sliceIndexes, stepModes, stepParameters):
            guard !stepPattern.isEmpty else { return [] }
            let normalizedStep = positiveModulo(stepIndex, stepPattern.count)
            guard stepPattern[normalizedStep] else { return [] }
            let resolvedIndexes = sliceIndexes.isEmpty ? [0] : sliceIndexes
            let sliceIndex = resolvedIndexes[normalizedStep % resolvedIndexes.count]
            let mode = stepModes[safe: normalizedStep] ?? .single
            let parameters = stepParameters[safe: normalizedStep] ?? .default
            return [
                GeneratedNote(
                    pitch: 60,
                    velocity: clampMIDI(NoteShape.default.velocity),
                    length: max(1, NoteShape.default.gateLength),
                    voiceTag: sliceVoiceTag(sliceIndex, runFromHere: mode == .runFromHere),
                    sliceParameters: parameters
                )
            ]
        }
    }

    static func processSourceNotes<R: RandomNumberGenerator>(
        _ notes: [GeneratedNote],
        through params: GeneratorParams,
        stepIndex: Int,
        clipChoices: [ClipPoolEntry],
        chordContext: Chord?,
        state: inout GeneratedSourceEvaluationState,
        stateScope: GeneratedSourceEvaluationScope = .primary,
        rng: inout R
    ) -> [GeneratedNote] {
        guard !notes.isEmpty else {
            return []
        }

        switch params {
        case let .mono(_, pitch, _):
            return notes.flatMap { sourceNote in
                transformedSourceNotes(
                    from: sourceNote,
                    pitches: [pitch],
                    stepIndex: stepIndex,
                    clipChoices: clipChoices,
                    chordContext: chordContext,
                    state: &state,
                    stateScope: stateScope,
                    rng: &rng
                )
            }
        case let .poly(_, pitches, _):
            return notes.flatMap { sourceNote in
                transformedSourceNotes(
                    from: sourceNote,
                    pitches: pitches,
                    stepIndex: stepIndex,
                    clipChoices: clipChoices,
                    chordContext: chordContext,
                    state: &state,
                    stateScope: stateScope,
                    rng: &rng
                )
            }
        case .progressionChords, .drum, .slice, .template:
            return notes
        }
    }

    private struct ResolvedHarmonicSidechain {
        var chord: Chord?
        var pitches: [Int]
        var scaleID: ScaleID?
    }

    private static func emittedSeeds<R: RandomNumberGenerator>(
        from trigger: TriggerStageNode,
        stepIndex: Int,
        totalSteps: Int,
        clipChoices: [ClipPoolEntry],
        rng: inout R,
        voiceTag: VoiceTag?
    ) -> [NoteSeed] {
        let stage = trigger.stepStage
        guard triggerFires(
            stage.algo,
            at: stepIndex,
            totalSteps: totalSteps,
            clipChoices: clipChoices,
            rng: &rng
        ) else {
            return []
        }

        return [NoteSeed(pitch: clampMIDI(stage.basePitch), voiceTag: voiceTag)]
    }

    private static func evaluatedPitchStage<R: RandomNumberGenerator>(
        _ pitchNode: PitchStageNode,
        seed: NoteSeed,
        stepIndex: Int,
        clipChoices: [ClipPoolEntry],
        chordContext: Chord?,
        laneIndex: Int,
        shape: NoteShape,
        state: inout GeneratedSourceEvaluationState,
        stateScope: GeneratedSourceEvaluationScope,
        rng: inout R
    ) -> [GeneratedNote] {
        let lastPitch = state.lastPitch(for: laneIndex, scope: stateScope)
        let pitches = transformedPitches(
            for: pitchNode.pitchStage,
            seed: seed,
            stepIndex: stepIndex,
            clipChoices: clipChoices,
            chordContext: chordContext,
            lastPitch: lastPitch,
            rng: &rng
        )
        if let last = pitches.last {
            state.setLastPitch(last, for: laneIndex, scope: stateScope)
        }
        return pitches.map { pitch in
            GeneratedNote(
                pitch: clampMIDI(pitch),
                velocity: clampMIDI(shape.velocity),
                length: max(1, shape.gateLength),
                voiceTag: seed.voiceTag
            )
        }
    }

    private static func transformedSourceNotes<R: RandomNumberGenerator>(
        from sourceNote: GeneratedNote,
        pitches: [PitchStageNode],
        stepIndex: Int,
        clipChoices: [ClipPoolEntry],
        chordContext: Chord?,
        state: inout GeneratedSourceEvaluationState,
        stateScope: GeneratedSourceEvaluationScope,
        rng: inout R
    ) -> [GeneratedNote] {
        let seed = NoteSeed(pitch: sourceNote.pitch, voiceTag: sourceNote.voiceTag)
        return pitches.enumerated().flatMap { laneIndex, pitchNode in
            let lastPitch = state.lastPitch(for: laneIndex, scope: stateScope)
            let resolvedPitches = transformedPitches(
                for: pitchNode.pitchStage,
                seed: seed,
                stepIndex: stepIndex,
                clipChoices: clipChoices,
                chordContext: chordContext,
                lastPitch: lastPitch,
                rng: &rng
            )
            if let last = resolvedPitches.last {
                state.setLastPitch(last, for: laneIndex, scope: stateScope)
            }
            return resolvedPitches.map { pitch in
                GeneratedNote(
                    pitch: clampMIDI(pitch),
                    velocity: clampMIDI(sourceNote.velocity),
                    length: max(1, sourceNote.length),
                    voiceTag: sourceNote.voiceTag,
                    sliceParameters: sourceNote.sliceParameters
                )
            }
        }
    }

    private static func transformedPitches<R: RandomNumberGenerator>(
        for stage: PitchStage,
        seed: NoteSeed,
        stepIndex: Int,
        clipChoices: [ClipPoolEntry],
        chordContext: Chord?,
        lastPitch: Int?,
        rng: inout R
    ) -> [Int] {
        let sidechain = resolvedSidechain(
            from: stage.harmonicSidechain,
            clipChoices: clipChoices,
            chordContext: chordContext
        )

        switch stage.algo {
        case let .manual(pitches, pickMode):
            guard !pitches.isEmpty else {
                return [seed.pitch]
            }
            switch pickMode {
            case .sequential:
                return [pitches[positiveModulo(stepIndex, pitches.count)]]
            case .random:
                return [pitches.randomElement(using: &rng) ?? seed.pitch]
            }

        case let .pool(root, scale, spread, selection, deviation):
            // Chord sidechain = PITCH-POOL FILTER ONLY (synthesis semantics
            // correction): it re-roots/re-scales the pool the picker draws
            // from and never touches the trigger stage.
            let effectiveRoot = sidechain.chord.map { Int($0.root) } ?? transposedRoot(seedPitch: seed.pitch, configuredRoot: root)
            let effectiveScale = sidechain.scaleID ?? scale
            return [pickPitch(
                using: .pool(
                    root: effectiveRoot,
                    scale: effectiveScale,
                    spread: spread,
                    selection: selection,
                    deviation: deviation
                ),
                lastPitch: lastPitch,
                scaleRoot: effectiveRoot,
                scaleID: effectiveScale,
                chord: sidechain.chord,
                stepIndex: stepIndex,
                rng: &rng
            )]

        case let .randomInScale(root, scale, spread):
            let effectiveRoot = transposedRoot(seedPitch: seed.pitch, configuredRoot: root)
            let effectiveScale = sidechain.scaleID ?? scale
            return [pickPitch(
                using: .randomInScale(root: effectiveRoot, scale: effectiveScale, spread: spread),
                lastPitch: lastPitch,
                scaleRoot: effectiveRoot,
                scaleID: effectiveScale,
                chord: sidechain.chord,
                stepIndex: stepIndex,
                rng: &rng
            )]

        case let .randomInChord(root, chord, inverted, spread):
            if let chordContext = sidechain.chord,
               let chordID = ChordID(rawValue: chordContext.chordType)
            {
                return [pickPitch(
                    using: .randomInChord(
                        root: Int(chordContext.root),
                        chord: chordID,
                        inverted: inverted,
                        spread: spread
                    ),
                    lastPitch: lastPitch,
                    scaleRoot: Int(chordContext.root),
                    scaleID: sidechain.scaleID ?? .major,
                    chord: chordContext,
                    stepIndex: stepIndex,
                    rng: &rng
                )]
            }

            if !sidechain.pitches.isEmpty {
                return [sidechain.pitches.randomElement(using: &rng) ?? seed.pitch]
            }

            let effectiveRoot = transposedRoot(seedPitch: seed.pitch, configuredRoot: root)
            let adapted = PitchAlgo.randomInChord(
                root: effectiveRoot,
                chord: chord,
                inverted: inverted,
                spread: spread
            )
            return [pickPitch(
                using: adapted,
                lastPitch: lastPitch,
                scaleRoot: effectiveRoot,
                scaleID: sidechain.scaleID ?? .major,
                chord: sidechain.chord,
                stepIndex: stepIndex,
                rng: &rng
            )]

        case let .intervalProb(root, scale, degreeWeights):
            let effectiveRoot = sidechain.chord.map { Int($0.root) } ?? transposedRoot(seedPitch: seed.pitch, configuredRoot: root)
            let effectiveScale = sidechain.scaleID ?? scale
            return [pickPitch(
                using: .intervalProb(root: effectiveRoot, scale: effectiveScale, degreeWeights: degreeWeights),
                lastPitch: lastPitch,
                scaleRoot: effectiveRoot,
                scaleID: effectiveScale,
                chord: sidechain.chord,
                stepIndex: stepIndex,
                rng: &rng
            )]

        case let .markov(root, scale, styleID, leap, color):
            let effectiveRoot = sidechain.chord.map { Int($0.root) } ?? transposedRoot(seedPitch: seed.pitch, configuredRoot: root)
            let effectiveScale = sidechain.scaleID ?? scale
            return [pickPitch(
                using: .markov(root: effectiveRoot, scale: effectiveScale, styleID: styleID, leap: leap, color: color),
                lastPitch: lastPitch,
                scaleRoot: effectiveRoot,
                scaleID: effectiveScale,
                chord: sidechain.chord,
                stepIndex: stepIndex,
                rng: &rng
            )]

        case let .fromClipPitches(clipID, pickMode):
            guard let clip = clipChoices.first(where: { $0.id == clipID }) else {
                return [seed.pitch]
            }
            let pool = clipPitchPool(for: clip)
            guard !pool.isEmpty else {
                return [seed.pitch]
            }
            switch pickMode {
            case .sequential:
                return [pool[positiveModulo(stepIndex, pool.count)]]
            case .random:
                return [pool.randomElement(using: &rng) ?? seed.pitch]
            }

        case .external:
            return [seed.pitch]
        }
    }

    private static func resolvedSidechain(
        from source: HarmonicSidechainSource,
        clipChoices: [ClipPoolEntry],
        chordContext: Chord?
    ) -> ResolvedHarmonicSidechain {
        switch source {
        case .none:
            return ResolvedHarmonicSidechain(chord: nil, pitches: [])
        case .projectChordContext:
            return ResolvedHarmonicSidechain(
                chord: chordContext,
                pitches: [],
                scaleID: chordContext.flatMap { ScaleID(rawValue: $0.scale) }
            )
        case let .clip(clipID):
            guard let clip = clipChoices.first(where: { $0.id == clipID }) else {
                return ResolvedHarmonicSidechain(chord: nil, pitches: [])
            }
            return ResolvedHarmonicSidechain(chord: nil, pitches: clipPitchPool(for: clip))
        }
    }

    private static func pickPitch<R: RandomNumberGenerator>(
        using algo: PitchAlgo,
        lastPitch: Int?,
        scaleRoot: Int,
        scaleID: ScaleID,
        chord: Chord?,
        stepIndex: Int,
        rng: inout R
    ) -> Int {
        algo.pick(
            context: PitchContext(
                lastPitch: lastPitch,
                scaleRoot: scaleRoot,
                scaleID: scaleID,
                currentChord: chord,
                stepIndex: stepIndex
            ),
            rng: &rng
        )
    }

    private static func triggerCycleLength(
        _ trigger: TriggerStageNode,
        clipChoices: [ClipPoolEntry]
    ) -> Int {
        _ = clipChoices
        switch trigger.stepStage.algo {
        case let .euclidean(_, steps, _):
            return max(steps, 1)
        case let .manual(pattern):
            return max(pattern.count, 1)
        case let .weighted(weights, steps, _):
            return max(steps, weights.count, 1)
        }
    }

    private static func laneFires<R: RandomNumberGenerator>(
        _ lane: ClipLane,
        rng: inout R
    ) -> Bool {
        let normalizedChance = min(max(lane.chance, 0), 1)
        if normalizedChance >= 1 {
            return true
        }
        if normalizedChance <= 0 {
            return false
        }
        return Double.random(in: 0..<1, using: &rng) < normalizedChance
    }

    private static func triggerFires<R: RandomNumberGenerator>(
        _ trigger: StepAlgo,
        at stepIndex: Int,
        totalSteps: Int,
        clipChoices: [ClipPoolEntry],
        rng: inout R
    ) -> Bool {
        _ = clipChoices
        return trigger.fires(at: stepIndex, totalSteps: totalSteps, rng: &rng)
    }

    private static func transposedRoot(seedPitch: Int, configuredRoot: Int) -> Int {
        seedPitch + (configuredRoot - 60)
    }

    /// CLUSTER character (shared with the WS4 weighted trigger's bipolar
    /// cluster factor): attraction (> 0) only admits candidates near an
    /// existing hit (rolls/flams grow around hits); repulsion (< 0) only
    /// admits candidates far from every hit (the pattern stays spread);
    /// neutral admits everything.
    private static func densityCandidateIsEligible(
        step: Int,
        stepCount: Int,
        hitSteps: Set<Int>,
        cluster: Double
    ) -> Bool {
        let count = max(stepCount, 1)
        let distances = hitSteps.map { hit -> Int in
            let raw = abs(step - hit)
            return min(raw, count - raw)
        }
        guard let nearest = distances.min() else {
            return false
        }
        let normalizedCluster = min(max(cluster, -1), 1)
        if normalizedCluster > 0 {
            let reach = max(1, Int((1 + normalizedCluster * 2).rounded(.down)))
            return nearest <= reach
        }
        if normalizedCluster < 0 {
            let farDistance = max(2, Int((Double(count) / 4 * abs(normalizedCluster)).rounded(.up)))
            return nearest >= farDistance
        }
        return true
    }

    /// Deterministic per-position inclusion fraction: FNV-1a over the pattern
    /// UUID bytes + step, mapped to [0, 1). Comparing against the density
    /// value gives loop-stable, monotonic-under-sweep ghost admission with no
    /// RNG anywhere near the tick path.
    private static func stableDensityFraction(patternID: UUID, step: Int) -> Double {
        let uuid = patternID.uuid
        let bytes: [UInt8] = [
            uuid.0, uuid.1, uuid.2, uuid.3,
            uuid.4, uuid.5, uuid.6, uuid.7,
            uuid.8, uuid.9, uuid.10, uuid.11,
            uuid.12, uuid.13, uuid.14, uuid.15
        ]
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in bytes {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        hash ^= UInt64(UInt32(bitPattern: Int32(step)))
        hash &*= 1_099_511_628_211
        // splitmix64-style avalanche: without it the step only reaches the
        // low bits weakly (one FNV multiply leaves the low 24 bits nearly
        // step-invariant, collapsing admission to all-or-nothing per pattern).
        hash ^= hash >> 30
        hash &*= 0xBF58_476D_1CE4_E5B9
        hash ^= hash >> 27
        hash &*= 0x94D0_49BB_1331_11EB
        hash ^= hash >> 31
        return Double(hash & 0x00FF_FFFF) / Double(0x0100_0000)
    }

    /// Nearest hit strictly before (`direction == -1`) or after (`+1`) the
    /// step, walking circularly.
    private static func nearestHit(
        from step: Int,
        in hitsByStep: [Int: DensitySourceHit],
        stepCount: Int,
        direction: Int
    ) -> DensitySourceHit? {
        guard !hitsByStep.isEmpty else { return nil }
        let count = max(stepCount, 1)
        for offset in 1..<count {
            let candidate = positiveModulo(step + direction * offset, count)
            if let hit = hitsByStep[candidate] {
                return hit
            }
        }
        return nil
    }

    private static func positiveModulo(_ value: Int, _ modulus: Int) -> Int {
        ((value % modulus) + modulus) % modulus
    }

    private static func clampMIDI(_ value: Int) -> Int {
        min(max(value, 0), 127)
    }

    private static func sliceVoiceTag(_ index: Int, runFromHere: Bool = false) -> String {
        "\(runFromHere ? "slice-run" : "slice")-\(max(0, index))"
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
