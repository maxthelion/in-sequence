import AVFoundation
import AudioToolbox
import Foundation

protocol TrackPlaybackSink: AnyObject {
    var displayName: String { get }
    var isAvailable: Bool { get }
    var availableInstruments: [AudioInstrumentChoice] { get }
    var selectedInstrument: AudioInstrumentChoice { get }
    var currentAudioUnit: AVAudioUnit? { get }
    func prepareIfNeeded()
    func preparePresetBrowser()
    func startIfNeeded()
    func stop()
    func shutdown()
    func setMix(_ mix: TrackMixSettings)
    /// Apply perform-layer mute as a ramped gain change (unified with the mixer
    /// mute carried in `setMix`). Default no-op for sinks without a gain stage.
    func setMuteGain(_ muted: Bool)
    func setOutputBusID(_ busID: UUID?)
    func setMeterTrackIDs(_ trackIDs: Set<UUID>)
    func setDestination(_ destination: Destination)
    func selectInstrument(_ choice: AudioInstrumentChoice)
    func captureStateBlob() throws -> Data?
    func play(noteEvents: [NoteEvent], bpm: Double, stepsPerBar: Int)
    /// Sample-accurate AU note trigger (Audio Engine Hard Rule 3, Phase 1).
    ///
    /// `noteOnSampleTime` is the absolute render frame the note-on should sound
    /// on — the SAME unified-clock frame a slice on this step receives
    /// (`AudioMasterClock.sampleTime(atMusicalSeconds:)`). `sampleRate` is the
    /// render sample rate, used to convert the per-note gate length into a
    /// note-off frame. When `noteOnSampleTime` is nil (no render origin /
    /// pre-render), the sink falls back to its immediate (non-stamped) path.
    ///
    /// Default-forwards to the legacy `play(noteEvents:bpm:stepsPerBar:)` so
    /// non-AU sinks (and test doubles) need not implement it.
    func play(
        noteEvents: [NoteEvent],
        bpm: Double,
        stepsPerBar: Int,
        noteOnSampleTime: AVAudioFramePosition?,
        sampleRate: Double
    )
}

extension TrackPlaybackSink {
    func preparePresetBrowser() {
        prepareIfNeeded()
    }

    func setOutputBusID(_ busID: UUID?) {}

    func setMuteGain(_ muted: Bool) {}

    /// Sinks that own a graph node may register it as the meter source for
    /// the tracks they play (roadmap 29). Default: no metering.
    func setMeterTrackIDs(_ trackIDs: Set<UUID>) {}

    /// Default: ignore the sample-accurate stamp and forward to the legacy
    /// immediate path. Only `AudioInstrumentHost` (the AU note sink) overrides
    /// this to schedule via `scheduleMIDIEventBlock` at `noteOnSampleTime`.
    func play(
        noteEvents: [NoteEvent],
        bpm: Double,
        stepsPerBar: Int,
        noteOnSampleTime: AVAudioFramePosition?,
        sampleRate: Double
    ) {
        play(noteEvents: noteEvents, bpm: bpm, stepsPerBar: stepsPerBar)
    }
}

final class AudioInstrumentHost: TrackPlaybackSink {
    private let audioGraph: MainAudioGraph
    private let queue = DispatchQueue(label: "ai.sequencer.SequencerAI.AudioInstrumentHost")
    private let snapshotLock = NSLock()
    /// Serializes mutation of, and scheduling against, the LIVE AU's internal
    /// state across thread domains (Phase 1 concurrency fix, defect D2). Two
    /// writers can otherwise touch the same `AUAudioUnit` with no mutual
    /// exclusion now that note scheduling left the main thread:
    ///   - note scheduling (`scheduleMIDIEventBlock`) runs on the host `queue`;
    ///   - `loadPreset` writes `au.currentPreset = ...` + `captureState` on MAIN;
    ///   - the lifecycle detach (`disconnectCurrentInstrument`) nils the live
    ///     instrument (on MAIN via `performOnMain`).
    /// Pre-P1 note-on ran on MAIN too (it hopped via `performOnMainAsync`), so it
    /// was serialized against `loadPreset` by the main thread; P1 moved it to the
    /// host queue, removing that implicit serialization. This lock restores it.
    ///
    /// THREADING / DEADLOCK D3: this is a LEAF lock — it is only ever held around
    /// non-blocking AU calls (`scheduleMIDIEventBlock`, `currentPreset=`,
    /// `captureState`, an instrument-reference read/write). It is NEVER held
    /// across a `queue.sync`/`DispatchQueue.main.sync` (or any cross-domain
    /// wait), so it cannot form the host-queue↔main AB-BA cycle that D3 is. Lock
    /// order is fixed and shallow: nothing acquires another host lock while
    /// holding `auMutationLock`, and nothing acquires `auMutationLock` while
    /// waiting on the other thread domain.
    private let auMutationLock = NSLock()
    private let instrumentChoices: [AudioInstrumentChoice]
    private let factory: AUAudioUnitFactory
    private let autoStartEngine: Bool

    private var instrument: AVAudioUnitMIDIInstrument?
    private var outputMixer: AVAudioMixerNode?
    private var shouldBeRunning = false
    private var currentMix = TrackMixSettings.default
    /// Perform-layer mute, applied as ramped gain alongside the mixer mute that
    /// rides in `currentMix.isMuted`. Effective mute = either is true; both
    /// resolve to the same ramped `outputMixer.outputVolume`.
    private var layerMuteGain = false
    private var currentOutputBusID: UUID?
    private var currentMeterTrackIDs: Set<UUID> = []
    private var currentChoice: AudioInstrumentChoice
    private var currentDestination: Destination
    private var instantiationGeneration: UInt64 = 0
    private var pendingLoadGeneration: UInt64?
    private var isShutdown = false
    private var snapshotChoice: AudioInstrumentChoice
    private var snapshotAudioUnit: AVAudioUnit?
    private var snapshotAvailable = false

    private func log(_ message: String) {
        NSLog("[AudioInstrumentHost] \(message)")
    }

    private func performOnMain(_ work: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                work()
            }
            return
        }

        TickPathMainSyncGuard.assertNotSyncingToMainFromTickPath("AudioInstrumentHost.performOnMain")
        // realtime-allow-main-sync: AU graph/setup control path guarded against tick-thread use. Test: RealtimePathLintTests.
        DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                work()
            }
        }
    }

    /// Fire-and-forget main hop for the CONTROL path only: the all-notes-off
    /// panic on stop / shutdown / disconnect / preset-browser-silence. The
    /// per-note trigger path no longer uses this — Phase 1 moved note-on/off to
    /// `scheduleMIDIEventBlock` (sample-stamped, no main hop). This hop must
    /// never sync-wait on main (deadlock D3 against main's queue.sync readouts).
    /// Runs inline when already on main so synchronous callers keep ordering.
    private func performOnMainAsync(_ work: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                work()
            }
            return
        }

        // realtime-allow-main-async: AU control-path all-notes-off panic only (stop/shutdown/preset-silence), NOT the note/tick trigger path. Test: RealtimePathLintTests.
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                work()
            }
        }
    }

    private func performOnMainThrowing<T>(_ work: @escaping @MainActor () throws -> T) throws -> T {
        if Thread.isMainThread {
            return try MainActor.assumeIsolated {
                try work()
            }
        }

        TickPathMainSyncGuard.assertNotSyncingToMainFromTickPath("AudioInstrumentHost.performOnMainThrowing")
        var output: T?
        var thrownError: Error?
        // realtime-allow-main-sync: AU read/setup control path guarded against tick-thread use. Test: RealtimePathLintTests.
        DispatchQueue.main.sync {
            do {
                output = try MainActor.assumeIsolated {
                    try work()
                }
            } catch {
                thrownError = error
            }
        }

        if let thrownError {
            throw thrownError
        }
        return output!
    }

    init(
        instrumentChoices: [AudioInstrumentChoice] = AudioInstrumentChoice.defaultChoices,
        initialInstrument: AudioInstrumentChoice = .builtInSynth,
        audioGraph: MainAudioGraph = MainAudioGraph(),
        autoStartEngine: Bool = true,
        instantiateAudioUnit: @escaping AUAudioUnitFactory.AudioUnitLoader = { description, completion in
            AVAudioUnit.instantiate(with: description, options: [], completionHandler: completion)
        }
    ) {
        let suppliedChoices = instrumentChoices.isEmpty ? [.builtInSynth] : instrumentChoices
        let resolvedChoices = AudioInstrumentChoice.deduplicated(suppliedChoices)
        self.instrumentChoices = resolvedChoices
        self.currentChoice = resolvedChoices.first(where: { $0 == initialInstrument }) ?? initialInstrument
        self.currentDestination = .auInstrument(componentID: self.currentChoice.audioComponentID, stateBlob: nil)
        self.audioGraph = audioGraph
        self.autoStartEngine = autoStartEngine
        self.factory = AUAudioUnitFactory(instantiateAudioUnit: instantiateAudioUnit)
        self.snapshotChoice = self.currentChoice
    }

    var displayName: String {
        withSnapshot { snapshotChoice.displayName }
    }

    var isAvailable: Bool {
        withSnapshot { snapshotAvailable }
    }

    var availableInstruments: [AudioInstrumentChoice] {
        instrumentChoices
    }

    var selectedInstrument: AudioInstrumentChoice {
        withSnapshot { snapshotChoice }
    }

    var currentAudioUnit: AVAudioUnit? {
        withSnapshot { snapshotAudioUnit }
    }

    func prepareIfNeeded() {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            guard !self.isShutdown else {
                self.log("prepareIfNeeded skipped - shutdown")
                return
            }
            self.log("prepareIfNeeded destination=\(self.currentDestination.summary) choice=\(self.currentChoice.displayName)")
            self.ensureInstrumentLoadedIfNeeded()
        }
    }

    func preparePresetBrowser() {
        silenceSnapshotInstrumentNotes()
        prepareIfNeeded()
    }

    func startIfNeeded() {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            guard !self.isShutdown else {
                self.log("startIfNeeded skipped - shutdown")
                return
            }
            self.shouldBeRunning = true
            self.log("startIfNeeded destination=\(self.currentDestination.summary)")
            self.ensureInstrumentLoadedIfNeeded()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else {
                return
            }

            self.shouldBeRunning = false
            self.log("stop")
            self.stopAllNotes()
        }
    }

    func shutdown() {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            guard !self.isShutdown else {
                self.log("shutdown skipped - already shutdown")
                return
            }

            self.log("shutdown start")
            self.isShutdown = true
            self.shouldBeRunning = false
            self.pendingLoadGeneration = nil
            self.instantiationGeneration &+= 1
            self.currentDestination = .none
            self.stopAllNotes()

            self.performOnMain {
                if let instrument = self.instrument {
                    self.log("shutdown detach instrument")
                    // realtime-allow-graph-mutation: AU shutdown teardown only, not tick dispatch. Test: RealtimePathLintTests.
                    self.audioGraph.disconnectOutput(instrument)
                    // realtime-allow-graph-mutation: AU shutdown teardown only, not tick dispatch. Test: RealtimePathLintTests.
                    self.audioGraph.detach(instrument)
                    self.instrument = nil
                }
                if let outputMixer = self.outputMixer {
                    // Forget this gain stage's recorded settled target so a future
                    // node recycled at the same ObjectIdentifier can't inherit a
                    // stale rest level (the outputMixer is a routing gain stage
                    // driven by MixerGainRamp; recycled-node hygiene).
                    MixerGainRamp.shared.forgetSettledTarget(for: outputMixer)
                    // realtime-allow-graph-mutation: AU shutdown teardown only, not tick dispatch. Test: RealtimePathLintTests.
                    self.audioGraph.disconnectOutput(outputMixer)
                    // realtime-allow-graph-mutation: AU shutdown teardown only, not tick dispatch. Test: RealtimePathLintTests.
                    self.audioGraph.detach(outputMixer)
                    self.outputMixer = nil
                }
                self.updateSnapshotInstrument(nil)
            }

            self.snapshotLock.lock()
            self.snapshotAvailable = false
            self.snapshotAudioUnit = nil
            self.snapshotLock.unlock()
            self.log("shutdown complete")
        }
    }

    func setMix(_ mix: TrackMixSettings) {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            guard !self.isShutdown else {
                return
            }

            self.currentMix = mix
            self.applyCurrentMix()
        }
    }

    func setOutputBusID(_ busID: UUID?) {
        queue.async { [weak self] in
            guard let self else { return }
            guard !self.isShutdown else { return }
            guard self.currentOutputBusID != busID else { return }

            self.currentOutputBusID = busID
            guard let outputMixer = self.outputMixer else { return }
            self.audioGraph.connectTrackOutput(outputMixer, to: busID, sends: self.currentMix.graphSendLevels)
            self.audioGraph.setTrackMeterSources(trackIDs: self.currentMeterTrackIDs, node: outputMixer)
        }
    }

    func setMeterTrackIDs(_ trackIDs: Set<UUID>) {
        queue.async { [weak self] in
            guard let self else { return }
            guard !self.isShutdown else { return }
            guard self.currentMeterTrackIDs != trackIDs else { return }

            self.currentMeterTrackIDs = trackIDs
            guard let outputMixer = self.outputMixer else { return }
            self.audioGraph.setTrackMeterSources(trackIDs: trackIDs, node: outputMixer)
        }
    }

    func setDestination(_ destination: Destination) {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            guard !self.isShutdown else {
                return
            }

            guard destination != self.currentDestination else {
                return
            }

            self.currentDestination = destination
            self.log("setDestination \(destination.summary)")
            switch destination {
            case let .auInstrument(componentID, _):
                self.currentChoice = self.instrumentChoices.first(where: { $0.audioComponentID == componentID })
                    ?? AudioInstrumentChoice(audioComponentID: componentID)
                self.updateSnapshotChoice(self.currentChoice)
                self.instantiationGeneration &+= 1
                self.pendingLoadGeneration = nil
                self.disconnectCurrentInstrument()
                if self.shouldBeRunning {
                    self.ensureInstrumentLoadedIfNeeded()
                }
            case .midi, .internalSampler, .sample, .slicer, .inheritGroup, .none:
                self.pendingLoadGeneration = nil
                self.disconnectCurrentInstrument()
            }
        }
    }

    func selectInstrument(_ choice: AudioInstrumentChoice) {
        setDestination(.auInstrument(componentID: choice.audioComponentID, stateBlob: nil))
    }

    func captureStateBlob() throws -> Data? {
        // Reads the live AU through the snapshot, WITHOUT joining the host
        // queue (deadlock D3): main sync-joining this queue while queued
        // items hop to main is an AB-BA cycle. The snapshot is updated under
        // snapshotLock whenever the instrument connects/disconnects.
        guard let instrument = withSnapshot({ snapshotAudioUnit }) else {
            return nil
        }
        return try factory.captureState(instrument)
    }

    /// Returns the live AU's preset lists plus the currently-loaded preset id, or
    /// `nil` if no AU is currently loaded. Empty arrays are valid — they mean the AU
    /// exposes no presets of that kind.
    func presetReadout() -> PresetReadout? {
        // Snapshot-based, no host-queue join (deadlock D3 — opening the
        // preset browser while notes play parked main behind a per-note
        // main hop).
        guard let instrument = withSnapshot({ snapshotAudioUnit }) else {
            return nil
        }
        let au = instrument.auAudioUnit
        let descriptors = AUPresetDescriptor.descriptors(
            factoryPresets: au.factoryPresets,
            userPresets: au.userPresets
        )
        return PresetReadout(
            factory: descriptors.factory,
            user: descriptors.user,
            currentID: AUPresetDescriptor.id(forCurrent: au.currentPreset)
        )
    }

    /// Sets the AU's current preset to the one matching `descriptor`, captures the
    /// resulting `fullState`, and returns the encoded blob.
    ///
    /// The caller is responsible for writing the blob into
    /// `Destination.auInstrument.stateBlob` via the document-command path.
    ///
    /// Throws `PresetLoadingError.presetNotFound` if the descriptor doesn't match any
    /// live preset (e.g. the AU was updated since the sheet opened).
    func loadPreset(_ descriptor: AUPresetDescriptor) throws -> Data? {
        silenceSnapshotInstrumentNotes()
        // Snapshot-based, no host-queue join (deadlock D3) — see
        // presetReadout.
        guard let instrument = withSnapshot({ snapshotAudioUnit }) else {
            throw PresetLoadingError.presetNotFound
        }

        let au = instrument.auAudioUnit
        guard let preset = AUPresetDescriptor.resolve(
            descriptor,
            factoryPresets: au.factoryPresets,
            userPresets: au.userPresets
        ) else {
            throw PresetLoadingError.presetNotFound
        }

        // NOTE: some AUs apply presets asynchronously via parameter-tree notifications.
        // Capturing state immediately after assignment may snapshot the prior state or
        // a partially-applied snapshot on such AUs. A correct fix would wait for the
        // parameter-tree change notification before calling captureState; that requires
        // async coordination with the AU notification thread.
        // TODO(u5): introduce a wait-for-parameter-tree-change here once the audio
        // ownership pass (U5) establishes a safe notification subscription pattern.
        //
        // Serialize the preset assignment + capture against host-queue note
        // scheduling (defect D2): both touch the SAME live AU's internal state.
        // The lock wraps only these two non-blocking AU calls and is never held
        // across a cross-domain wait, so it cannot recreate deadlock D3.
        auMutationLock.lock()
        defer { auMutationLock.unlock() }
        au.currentPreset = preset
        return try factory.captureState(instrument)
    }

    func play(noteEvents: [NoteEvent], bpm: Double, stepsPerBar: Int) {
        play(
            noteEvents: noteEvents,
            bpm: bpm,
            stepsPerBar: stepsPerBar,
            noteOnSampleTime: nil,
            sampleRate: 0
        )
    }

    /// Sample-accurate AU note trigger (Audio Engine Hard Rule 3, Phase 1 —
    /// the flam fix). Schedules note-on and note-off on the AU's render
    /// timeline via `scheduleMIDIEventBlock`, so an AU note and a slice on the
    /// same step land on the SAME frame. No main-thread hop on the note path.
    ///
    /// `noteOnSampleTime` is the absolute render frame the note-on sounds on —
    /// the unified-clock frame (`AudioMasterClock.sampleTime(atMusicalSeconds:)`)
    /// that a slice on this step also receives. The AU's `scheduleMIDIEventBlock`
    /// takes an `AUEventSampleTime` on the AU's own render timeline; for an AU
    /// hosted in AVAudioEngine that timeline is the engine render `sampleTime`
    /// (one render clock drives every attached node), so the absolute render
    /// frame the unified clock computes IS a valid `AUEventSampleTime` and
    /// matches the slice exactly.
    ///
    /// When `noteOnSampleTime` is nil (no render origin yet, or sample-time
    /// scheduling unavailable on the AU), falls back to immediate scheduling
    /// (`AUEventSampleTimeImmediate`) — still off-main via the MIDI block, never
    /// a `startNote` main hop.
    func play(
        noteEvents: [NoteEvent],
        bpm: Double,
        stepsPerBar: Int,
        noteOnSampleTime: AVAudioFramePosition?,
        sampleRate: Double
    ) {
        guard !noteEvents.isEmpty else {
            return
        }

        queue.async { [weak self] in
            guard let self else {
                return
            }
            guard !self.isShutdown else {
                return
            }

            guard let instrument = self.instrument else {
                self.ensureInstrumentLoadedIfNeeded()
                return
            }

            self.startEngineIfPossible()

            // Detached/teardown guard (defect D4 lifecycle half): capture the
            // live AU once and re-check we are not shutting down. A note must
            // never schedule onto a detached/deallocated/mid-reset AU. The
            // `instrument` reference is mutated (set to nil on detach) on MAIN;
            // we capture the `auAudioUnit` here on the host queue and only
            // schedule against that captured reference under `auMutationLock`,
            // so a concurrent `loadPreset`/detach can't interleave with the
            // scheduling block on the same live AU.
            let au = instrument.auAudioUnit
            guard let scheduleMIDI = au.scheduleMIDIEventBlock else {
                // AU does not expose a MIDI scheduling block. Without it there is
                // no sample-stamped path; do NOT reintroduce the deleted
                // main-hop/startNote debt. The note is dropped (rare for MIDI
                // instruments, which all vend this block). Logged for evidence.
                self.log("play dropped — AU exposes no scheduleMIDIEventBlock choice=\(self.currentChoice.displayName)")
                return
            }

            // Serialize against `loadPreset`'s `currentPreset=`/captureState and
            // the lifecycle detach (defect D2). The lock wraps ONLY the
            // scheduleMIDIEventBlock calls (non-blocking, RT-safe — the block
            // copies the bytes synchronously), never a cross-domain wait, so D3
            // cannot recur. We re-confirm under the lock that this AU is still
            // the live instrument and the host is not shutting down before
            // touching it.
            self.auMutationLock.lock()
            defer { self.auMutationLock.unlock() }
            guard !self.isShutdown, self.instrument?.auAudioUnit === au else {
                self.log("play dropped — AU detached/torn down before scheduling choice=\(self.currentChoice.displayName)")
                return
            }

            // Past-frame floor (defect D4): the unified-clock note-on frame is an
            // absolute OUTPUT-node render frame; the AU honours an
            // `AUEventSampleTime` on its OWN render timeline. For an AU hosted in
            // AVAudioEngine one render clock drives every attached node, so the
            // output frame and the AU render frame share a base — BUT origin/now
            // skew (a stamp computed against an origin captured slightly before
            // the AU's live render position, or a late pump wake) can yield a
            // frame already in the AU's past. Handing the AU a past frame is
            // undefined/dropped, so we clamp such a note to immediate
            // (`AUEventSampleTimeImmediate`) rather than into the past. The AU's
            // current render frame is read from its `lastRenderTime` (nil before
            // the first render → no floor, fallback already handles pre-render).
            //
            // HUMAN ACOUSTIC RISK (not machine-verifiable here): that the
            // output-node render frame and the AU's internal render frame are the
            // SAME absolute frame (render-clock base equality) is an Apple
            // AVAudioEngine property we rely on but cannot assert offline — it is
            // the documented human acoustic check (a real AU on the device).
            let currentRenderFrame = instrument.lastRenderTime?.sampleTime
            for event in noteEvents where event.gate {
                let stamps = Self.noteStamps(
                    noteOnSampleTime: noteOnSampleTime,
                    length: event.length,
                    bpm: bpm,
                    stepsPerBar: stepsPerBar,
                    sampleRate: sampleRate,
                    currentRenderFrame: currentRenderFrame
                )
                Self.scheduleNote(
                    event,
                    stamps: stamps,
                    using: scheduleMIDI
                )
            }
        }
    }

    /// AU MIDI note-on / note-off bytes for channel 0 (status 0x90 / 0x80).
    ///
    /// KNOWN LIMITATION (Phase 1 point 5 — same-pitch overlap on channel 0): all
    /// notes are scheduled on MIDI channel 0. If the SAME pitch retriggers while
    /// a previous long gate is still ringing, this note-off (`0x80 pitch`) can
    /// cancel the NEW note-on instead of the old one — standard MIDI has no
    /// per-voice note identity, only (channel, pitch). This is NOT new (the
    /// pre-P1 single-channel `startNote`/`stopNote` path had the same property);
    /// sample-accurate stamping only makes the ordering deterministic. A real fix
    /// is per-voice channel rotation / voice allocation, deliberately OUT OF
    /// SCOPE for this task (see docs/plans/2026-06-24-sample-accurate-timing.md).
    private static func scheduleNote(
        _ event: NoteEvent,
        stamps: AUNoteStamps,
        using scheduleMIDI: AUScheduleMIDIEventBlock
    ) {
        let velocity = event.velocity
        let pitch = event.pitch
        // Note-on (0x90), then note-off (0x80) one gate-length later, both
        // stamped on the AU render timeline. scheduleMIDIEventBlock copies the
        // bytes synchronously, so a stack array is RT-safe here.
        let noteOn: [UInt8] = [0x90, pitch, velocity]
        noteOn.withUnsafeBufferPointer { buffer in
            scheduleMIDI(stamps.noteOn, 0, buffer.count, buffer.baseAddress!)
        }
        let noteOff: [UInt8] = [0x80, pitch, 0]
        noteOff.withUnsafeBufferPointer { buffer in
            scheduleMIDI(stamps.noteOff, 0, buffer.count, buffer.baseAddress!)
        }
    }

    private func stopAllNotes() {
        guard let instrument else {
            return
        }

        // Control-path all-notes-off panic (stop/shutdown/disconnect), NOT the
        // note/tick trigger path. Async-to-main avoids deadlock D3.
        Self.stopAllNotes(on: instrument, performOnMain: performOnMainAsync)
    }

    private func silenceSnapshotInstrumentNotes() {
        guard let instrument = withSnapshot({ snapshotAudioUnit as? AVAudioUnitMIDIInstrument }) else {
            return
        }

        Self.stopAllNotes(on: instrument, performOnMain: performOnMainAsync)
    }

    private static func stopAllNotes(
        on instrument: AVAudioUnitMIDIInstrument,
        performOnMain: (@escaping @MainActor () -> Void) -> Void
    ) {
        performOnMain {
            for pitch in UInt8(0)...UInt8(127) {
                // realtime-allow-control-stopnote: all-notes-off panic on stop/shutdown/preset-silence, NOT the note/tick trigger path (which is sample-stamped via scheduleMIDIEventBlock). Test: RealtimePathLintTests.
                instrument.stopNote(pitch, onChannel: 0)
            }
        }
    }

    private func instantiate(choice: AudioInstrumentChoice, stateBlob: Data?, generation: UInt64) {
        pendingLoadGeneration = generation
        log("instantiate choice=\(choice.displayName) generation=\(generation) hasState=\(stateBlob != nil)")
        factory.instantiate(choice.audioComponentID, stateBlob: stateBlob) { [weak self] result in
            guard let self else {
                return
            }

            self.queue.async {
                guard generation == self.instantiationGeneration else {
                    return
                }
                guard !self.isShutdown else {
                    return
                }
                guard self.pendingLoadGeneration == generation else {
                    return
                }
                self.pendingLoadGeneration = nil
                guard case let .success(audioUnit) = result,
                      let instrument = audioUnit as? AVAudioUnitMIDIInstrument
                else {
                    if case let .failure(error) = result {
                        self.log("instantiate failed choice=\(choice.displayName) generation=\(generation) error=\(String(describing: error))")
                    } else {
                        self.log("instantiate returned non-MIDI instrument choice=\(choice.displayName) generation=\(generation)")
                    }
                    self.handleLoadFailure(for: choice, generation: generation)
                    return
                }

                if let attachedEngine = instrument.engine, attachedEngine !== self.audioGraph.engine {
                    self.log("instantiate returned instrument already attached to another engine choice=\(choice.displayName)")
                    self.handleLoadFailure(for: choice, generation: generation)
                    return
                }

                self.log("instantiate success choice=\(choice.displayName) generation=\(generation)")
                self.connectLoadedInstrument(instrument)
            }
        }
    }

    private func connectLoadedInstrument(_ nextInstrument: AVAudioUnitMIDIInstrument) {
        log("connectLoadedInstrument")
        disconnectCurrentInstrument()
        performOnMain {
            // Set the live reference under `auMutationLock` to pair with the
            // detach nil-out and the note path's `=== au` guard (defect D2/D4).
            self.auMutationLock.lock()
            self.instrument = nextInstrument
            self.auMutationLock.unlock()
            self.updateSnapshotInstrument(nextInstrument)
            if nextInstrument.engine == nil {
                // realtime-allow-graph-mutation: AU load/setup connection only, not tick dispatch. Test: RealtimePathLintTests.
                self.audioGraph.attach(nextInstrument)
            }
            let mixer = self.outputMixer ?? AVAudioMixerNode()
            if self.outputMixer == nil {
                self.outputMixer = mixer
                // realtime-allow-graph-mutation: AU load/setup connection only, not tick dispatch. Test: RealtimePathLintTests.
                self.audioGraph.attach(mixer)
                self.audioGraph.connectTrackOutput(mixer, to: self.currentOutputBusID, sends: self.currentMix.graphSendLevels)
                self.audioGraph.setTrackMeterSources(trackIDs: self.currentMeterTrackIDs, node: mixer)
            }
            if self.audioGraph.engine.outputConnectionPoints(for: nextInstrument, outputBus: 0).isEmpty {
                // realtime-allow-graph-mutation: AU load/setup connection only, not tick dispatch. Test: RealtimePathLintTests.
                self.audioGraph.connect(nextInstrument, to: mixer)
            }
        }
        applyCurrentMix()
        startEngineIfPossible()
    }

    private func ensureInstrumentLoadedIfNeeded() {
        guard case let .auInstrument(_, stateBlob) = currentDestination else {
            log("ensureInstrumentLoadedIfNeeded no AU destination")
            disconnectCurrentInstrument()
            return
        }
        guard instrument == nil else {
            log("ensureInstrumentLoadedIfNeeded already loaded")
            startEngineIfPossible()
            return
        }
        guard pendingLoadGeneration != instantiationGeneration else {
            log("ensureInstrumentLoadedIfNeeded load already pending generation=\(instantiationGeneration)")
            return
        }

        instantiate(choice: currentChoice, stateBlob: stateBlob, generation: instantiationGeneration)
    }

    private func handleLoadFailure(for choice: AudioInstrumentChoice, generation: UInt64) {
        guard generation == instantiationGeneration else {
            return
        }

        pendingLoadGeneration = nil
        disconnectCurrentInstrument()
        log("handleLoadFailure choice=\(choice.displayName) generation=\(generation)")
        guard choice != .builtInSynth,
              let fallbackChoice = instrumentChoices.first(where: { $0 == .builtInSynth })
        else {
            return
        }

        currentChoice = fallbackChoice
        updateSnapshotChoice(fallbackChoice)
        currentDestination = .auInstrument(componentID: fallbackChoice.audioComponentID, stateBlob: nil)
        instantiationGeneration &+= 1
        instantiate(choice: fallbackChoice, stateBlob: nil, generation: instantiationGeneration)
    }

    private func disconnectCurrentInstrument() {
        stopAllNotes()
        guard let instrument else {
            return
        }

        performOnMain {
            self.log("disconnectCurrentInstrument detach instrument")
            // realtime-allow-graph-mutation: AU destination teardown only, not tick dispatch. Test: RealtimePathLintTests.
            self.audioGraph.disconnectOutput(instrument)
            // realtime-allow-graph-mutation: AU destination teardown only, not tick dispatch. Test: RealtimePathLintTests.
            self.audioGraph.detach(instrument)
            // Nil the live reference under `auMutationLock` so the host-queue
            // note path's `instrument?.auAudioUnit === au` guard observes the
            // detach atomically and skips scheduling onto the torn-down AU
            // (defect D2/D4 lifecycle). Leaf-lock, no cross-domain wait inside.
            self.auMutationLock.lock()
            self.instrument = nil
            self.auMutationLock.unlock()
            self.updateSnapshotInstrument(nil)
        }
    }

    private func startEngineIfPossible() {
        guard autoStartEngine, shouldBeRunning, instrument != nil else {
            return
        }

        do {
            try audioGraph.start()
            log("engine started")
        } catch {
            log("engine start failed error=\(String(describing: error))")
        }
    }

    private func applyCurrentMix() {
        guard let outputMixer else {
            return
        }

        let effectivelyMuted = currentMix.isMuted || layerMuteGain
        let targetVolume: Float = effectivelyMuted ? 0 : Float(currentMix.clampedLevel)
        performOnMain { [currentMix] in
            outputMixer.pan = Float(currentMix.clampedPan)
            // Mute applies as a short ramped gain (mirrors bus-mute shape) so a
            // ringing AU voice is cut/restored without a click and without
            // waiting for the next trigger.
            MixerGainRamp.shared.ramp(outputMixer, to: targetVolume)
            self.audioGraph.setTrackSendLevels(
                outputMixer,
                sendA: currentMix.sendA,
                sendB: currentMix.sendB
            )
        }
    }

    /// The live shared output mixer's current `outputVolume` — the gain that
    /// mute (mixer OR layer) ramps. Engine-truth readout for the routing-stress
    /// gate, which previously could only read sample-track gain (AU tracks read
    /// `n/a`). Returns nil when the host has no output mixer yet (not loaded).
    /// NOTE: for `.inheritGroup` shared hosts this is ONE value for the whole
    /// group — there is no per-member gain stage (see the F1.1/F2.1 finding).
    func currentOutputGainForTesting() -> Float? {
        performOnMainReturningOptional { [weak self] in
            self?.outputMixer?.outputVolume
        }
    }

    /// The bus the host has ACTUALLY routed its shared output to (nil = master).
    /// Engine-truth for the gate: set inside `setOutputBusID`, which is the call
    /// that drives the live `connectTrackOutput`. Outer nil = host not loaded.
    func currentOutputBusIDForTesting() -> UUID?? {
        // currentOutputBusID is mutated on the host queue; read it there to
        // avoid a torn read against an in-flight setOutputBusID.
        var result: UUID?? = .none
        queue.sync {
            result = self.outputMixer == nil ? UUID??.none : .some(self.currentOutputBusID)
        }
        return result
    }

    private func performOnMainReturningOptional<T>(_ work: @escaping @MainActor () -> T?) -> T? {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { work() }
        }
        var output: T?
        // realtime-allow-main-sync: test-only readout, not tick dispatch. Test: RealtimePathLintTests.
        DispatchQueue.main.sync {
            output = MainActor.assumeIsolated { work() }
        }
        return output
    }

    /// Perform-layer mute as a ramped gain change (unified with mixer mute).
    func setMuteGain(_ muted: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            guard !self.isShutdown else { return }
            guard self.layerMuteGain != muted else { return }
            self.layerMuteGain = muted
            self.applyCurrentMix()
        }
    }

    // MARK: - Parameter readout (macro picker support)

    /// Returns a flat list of all writable parameters exposed by the currently-loaded AU.
    ///
    /// Returns nil if no AU is loaded. Must be called on the main thread.
    /// The caller is responsible for caching; this method always re-reads from the live
    /// `parameterTree` (which is safe to call on main thread).
    func parameterReadout() -> [AUParameterDescriptor]? {
        assert(Thread.isMainThread, "parameterReadout must be called on main thread")
        guard let au = withSnapshot({ snapshotAudioUnit }),
              let tree = au.auAudioUnit.parameterTree
        else {
            return nil
        }

        return Self.parameterDescriptors(from: tree)
    }

    static func parameterDescriptors(from tree: AUParameterTree) -> [AUParameterDescriptor] {
        descriptors(from: tree.children, ancestorNames: [])
    }

    private static func descriptors(
        from nodes: [AUParameterNode],
        ancestorNames: [String]
    ) -> [AUParameterDescriptor] {
        nodes.flatMap { node -> [AUParameterDescriptor] in
            if let group = node as? AUParameterGroup {
                var nextAncestors = ancestorNames
                nextAncestors.append(group.displayName)
                return descriptors(from: group.children, ancestorNames: nextAncestors)
            }

            guard let param = node as? AUParameter,
                  param.flags.contains(.flag_IsWritable)
            else {
                return []
            }

            return [
                AUParameterDescriptor(
                    address: param.address,
                    identifier: param.identifier,
                    displayName: param.displayName,
                    minValue: Double(param.minValue),
                    maxValue: Double(param.maxValue),
                    defaultValue: Double(param.value),
                    unit: unitString(for: param.unit),
                    group: ancestorNames,
                    isWritable: true
                )
            ]
        }
    }

    private static func unitString(for unit: AudioUnitParameterUnit) -> String? {
        switch unit {
        case .hertz: return "Hz"
        case .decibels: return "dB"
        case .linearGain: return "gain"
        case .percent: return "%"
        case .seconds: return "s"
        case .milliseconds: return "ms"
        case .beats: return "beats"
        case .octaves: return "oct"
        case .cents: return "cents"
        case .absoluteCents: return "¢"
        case .BPM: return "BPM"
        case .degrees: return "°"
        case .pan: return "pan"
        case .indexed, .boolean, .generic, .customUnit, .ratio: return nil
        default: return nil
        }
    }

    /// The note-on / note-off `AUEventSampleTime` pair for one note.
    struct AUNoteStamps: Equatable {
        let noteOn: AUEventSampleTime
        let noteOff: AUEventSampleTime
    }

    /// PURE stamp math (Audio Engine Hard Rule 3 / Phase 1 zero-flam gate). No
    /// AU instance, no engine, no clock — fully unit-testable.
    ///
    /// Given the note-on absolute render frame (`noteOnSampleTime`, the SAME
    /// unified-clock frame `AudioMasterClock.sampleTime(atMusicalSeconds:)`
    /// hands a slice on this step) and the per-note gate length, returns the
    /// note-on and note-off `AUEventSampleTime`s on the AU render timeline.
    ///
    /// Zero-flam invariant: `noteStamps(noteOnSampleTime: F, ...).noteOn == F`.
    /// So the AU note-on lands on the EXACT frame the matching slice does — the
    /// stamp-level zero-flam assertion (the acoustic level is the human's).
    ///
    /// Gate length in frames = `length` steps × frames-per-step, where
    /// frames-per-step = `secondsPerStep(bpm,stepsPerBar) × sampleRate`. The
    /// note-off is `noteOn + max(1, gateFrames)` (always at least one frame
    /// after the note-on so a zero/under-rounded length never produces a
    /// degenerate note-off at or before the note-on).
    ///
    /// When `noteOnSampleTime` is nil (no render origin), both stamps are
    /// `AUEventSampleTimeImmediate` — the AU schedules them at the head of the
    /// next render cycle (still off-main, still via the MIDI block).
    ///
    /// `currentRenderFrame` is the AU's current render `sampleTime` (its
    /// `lastRenderTime`), used as a PAST-FRAME FLOOR (defect D4): if the computed
    /// note-on frame is < the AU's current render frame (origin/now skew, a late
    /// pump wake), handing the AU a past frame is undefined/dropped, so BOTH
    /// stamps fall back to immediate (the AU sounds it at the head of the next
    /// render cycle) — never a past frame. nil (no render yet) means no floor.
    static func noteStamps(
        noteOnSampleTime: AVAudioFramePosition?,
        length: UInt16,
        bpm: Double,
        stepsPerBar: Int,
        sampleRate: Double,
        currentRenderFrame: AVAudioFramePosition? = nil
    ) -> AUNoteStamps {
        guard let noteOnSampleTime, sampleRate > 0 else {
            return AUNoteStamps(
                noteOn: AUEventSampleTime(AUEventSampleTimeImmediate),
                noteOff: AUEventSampleTime(AUEventSampleTimeImmediate)
            )
        }

        // Past-frame guard (D4): a note-on frame already behind the AU's live
        // render position can never sound at that frame — clamp to immediate
        // rather than hand the AU a past frame.
        if let currentRenderFrame, noteOnSampleTime < currentRenderFrame {
            return AUNoteStamps(
                noteOn: AUEventSampleTime(AUEventSampleTimeImmediate),
                noteOff: AUEventSampleTime(AUEventSampleTimeImmediate)
            )
        }

        let secondsPerStep = (60.0 / max(bpm, 1)) * (4.0 / Double(max(stepsPerBar, 1)))
        let gateSeconds = secondsPerStep * Double(length)
        let gateFrames = AVAudioFramePosition((gateSeconds * sampleRate).rounded())
        let noteOff = noteOnSampleTime + max(1, gateFrames)
        return AUNoteStamps(
            noteOn: AUEventSampleTime(noteOnSampleTime),
            noteOff: AUEventSampleTime(noteOff)
        )
    }

    private func withSnapshot<T>(_ body: () -> T) -> T {
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        return body()
    }

    private func updateSnapshotChoice(_ choice: AudioInstrumentChoice) {
        snapshotLock.lock()
        snapshotChoice = choice
        snapshotLock.unlock()
    }

    private func updateSnapshotInstrument(_ instrument: AVAudioUnit?) {
        snapshotLock.lock()
        snapshotAudioUnit = instrument
        snapshotAvailable = instrument != nil
        snapshotLock.unlock()
    }
}
