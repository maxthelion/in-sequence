import Foundation

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
        rng: inout R
    ) -> [GeneratedNote] {
        let lastPitch = state.lastPitch(for: laneIndex)
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
            state.setLastPitch(last, for: laneIndex)
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
        rng: inout R
    ) -> [GeneratedNote] {
        let seed = NoteSeed(pitch: sourceNote.pitch, voiceTag: sourceNote.voiceTag)
        return pitches.enumerated().flatMap { laneIndex, pitchNode in
            let lastPitch = state.lastPitch(for: laneIndex)
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
                state.setLastPitch(last, for: laneIndex)
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
