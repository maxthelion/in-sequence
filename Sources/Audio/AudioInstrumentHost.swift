import AVFoundation
import AudioToolbox
import Foundation

protocol TrackPlaybackSink: AnyObject {
    var displayName: String { get }
    var isAvailable: Bool { get }
    var availableInstruments: [AudioInstrumentChoice] { get }
    var selectedInstrument: AudioInstrumentChoice { get }
    var currentAudioUnit: AVAudioUnit? { get }
    /// True when this sink can accept the first transport tick without silently
    /// dropping it. AU hosts report false while a plugin is still instantiating.
    var isReadyForTransportStart: Bool { get }
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
    /// `noteOnSampleTime` is the absolute OUTPUT-node render frame the note-on
    /// should sound on — the SAME unified-clock frame a slice on this step
    /// receives (`AudioMasterClock.sampleTime(atMusicalSeconds:)`). Sinks whose
    /// event clock is NOT the output timeline translate it themselves (the AU
    /// host maps it onto the AU's own render timeline — see
    /// `AudioInstrumentHost.auTimelineNoteOnFrame`). `sampleRate` is the OUTPUT
    /// render sample rate the frame is expressed in. When `noteOnSampleTime` is
    /// nil (no render origin / pre-render), the sink falls back to its
    /// immediate (non-stamped) path.
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
    var isReadyForTransportStart: Bool {
        true
    }

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
    /// Rotate note voices across MIDI channels so a stale note-off for a long
    /// gate cannot silence a newer retrigger of the same pitch. Channel 10 is
    /// excluded because General MIDI instruments commonly reserve it for drums.
    static let midiVoiceChannels: [UInt8] = Array(0...8) + Array(10...15)

    static func midiVoiceChannel(forAllocation allocation: Int) -> UInt8 {
        midiVoiceChannels[max(0, allocation) % midiVoiceChannels.count]
    }

    static func noteOnBytes(pitch: UInt8, velocity: UInt8, channel: UInt8) -> [UInt8] {
        [0x90 | (channel & 0x0F), pitch, velocity]
    }

    static func noteOffBytes(pitch: UInt8, channel: UInt8) -> [UInt8] {
        [0x80 | (channel & 0x0F), pitch, 0]
    }

    private let audioGraph: MainAudioGraph
    private let queue = DispatchQueue(label: "ai.sequencer.SequencerAI.AudioInstrumentHost")
    private let snapshotLock = NSLock()
    private var nextMIDIVoiceChannelIndex = 0
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
    /// Snapshot of the output routing (mixer presence + bus) for the test
    /// readouts. Published under `snapshotLock` whenever `outputMixer` /
    /// `currentOutputBusID` change, so `current*ForTesting()` can read engine-
    /// truth WITHOUT a `queue.sync` onto the host queue. A bare `queue.sync`
    /// from the main thread deadlocks against the host queue's own
    /// `connectLoadedInstrument -> performOnMain` (main.sync) during AU setup —
    /// an AB-BA cycle that froze the app when the command-channel status writer
    /// polled these on main while an AU was instantiating (found in the
    /// 2026-06-26 real-AU verification pass). Same rationale as `snapshotAudioUnit`.
    private var snapshotOutputMixer: AVAudioMixerNode?
    private var snapshotOutputBusID: UUID?

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

    var isReadyForTransportStart: Bool {
        withSnapshot { snapshotAvailable }
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

            self.rampOutputMixerToSilenceBeforeGraphTeardown(reason: "shutdown")
            self.performOnMain {
                if let instrument = self.instrument {
                    self.log("shutdown detach instrument")
                    // realtime-allow-graph-mutation: AU shutdown teardown after outputMixer ramp-to-silence, not tick dispatch. Test: RealtimePathLintTests.
                    self.audioGraph.disconnectOutput(instrument)
                    // realtime-allow-graph-mutation: AU shutdown teardown after outputMixer ramp-to-silence, not tick dispatch. Test: RealtimePathLintTests.
                    self.audioGraph.detach(instrument)
                    self.instrument = nil
                }
                if let outputMixer = self.outputMixer {
                    // Forget this gain stage's recorded settled target so a future
                    // node recycled at the same ObjectIdentifier can't inherit a
                    // stale rest level (the outputMixer is a routing gain stage
                    // driven by MixerGainRamp; recycled-node hygiene).
                    MixerGainRamp.shared.forgetSettledTarget(for: outputMixer)
                    // realtime-allow-graph-mutation: AU shutdown teardown after outputMixer ramp-to-silence, not tick dispatch. Test: RealtimePathLintTests.
                    self.audioGraph.disconnectOutput(outputMixer)
                    // realtime-allow-graph-mutation: AU shutdown teardown after outputMixer ramp-to-silence, not tick dispatch. Test: RealtimePathLintTests.
                    self.audioGraph.detach(outputMixer)
                    self.outputMixer = nil
                    self.updateSnapshotOutput()
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
            self.updateSnapshotOutput()
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

        // Clear any note the patch reconfiguration left ringing. Bug
        // 20260629-101847: switching a preset mid-playback could leave a note
        // hung (~to the end of the bar). All-Notes-Off (CC 123) on channel 0 is
        // sent sample-stamped through the AU's OWN MIDI block here, so it is
        // ordered deterministically right after `currentPreset =` on this thread
        // — unlike the async main-hop `stopNote` panic, which races the
        // reconfiguration. RT-safe: the block copies the bytes synchronously
        // (same path as the program-change quirk handling below). A no-op when
        // nothing is held.
        if let scheduleMIDI = au.scheduleMIDIEventBlock {
            Self.scheduleAllNotesOff(using: scheduleMIDI)
        }

        // SAFE-BY-CONSTRUCTION program-change quirk handling.
        //
        // A few AUs (Arturia Analog Lab V et al.) vend factory presets that are
        // really MIDI program-change SLOTS, named literally "ProgramChange1",
        // "ProgramChange2", … . On those AUs `currentPreset =` alone does NOT
        // audibly switch the patch (this bug) — the patch only switches on a real
        // MIDI Program Change. So ONLY for a factory preset whose NAME matches the
        // "ProgramChangeN" pattern do we send a real Program Change, and we derive
        // the program number from the NAME (the AU's own declared program), NOT
        // from `preset.number` (which is merely the factory-presets array index and
        // would clamp/collide).
        //
        // A normal AU's factory presets ("Warm Pad", "Bright Lead") do NOT match
        // the pattern, so NO Program Change is sent and the common case — where
        // `currentPreset =` is authoritative — cannot regress (no double-switch).
        // User presets are real saved AU states and never get a Program Change.
        if descriptor.kind == .factory,
           let scheduleMIDI = au.scheduleMIDIEventBlock,
           let programNumber = Self.programNumberFromPresetName(preset.name) {
            let bytes = Self.programChangeBytes(programNumber: programNumber)
            bytes.withUnsafeBufferPointer { buffer in
                scheduleMIDI(
                    AUEventSampleTime(AUEventSampleTimeImmediate),
                    0,
                    buffer.count,
                    buffer.baseAddress!
                )
            }
        }

        return try factory.captureState(instrument)
    }

    /// MIDI All-Notes-Off (Control Change 123, value 0). Sent on every allocated
    /// voice channel after a preset switch to clear notes left ringing by patch
    /// reconfiguration (bug 20260629-101847).
    static func allNotesOffBytes(channel: UInt8 = 0) -> [UInt8] {
        [0xB0 | (channel & 0x0F), 0x7B, 0x00]
    }

    /// Send MIDI CC 123 through the AU's own sample-stamped MIDI block. This is
    /// used on control paths only (transport stop / preset change), never as a
    /// tick-path substitute for normal note-off scheduling.
    static func scheduleAllNotesOff(using scheduleMIDI: AUScheduleMIDIEventBlock) {
        for channel in midiVoiceChannels {
            let allNotesOff = allNotesOffBytes(channel: channel)
            allNotesOff.withUnsafeBufferPointer { buffer in
                scheduleMIDI(
                    AUEventSampleTime(AUEventSampleTimeImmediate),
                    0,
                    buffer.count,
                    buffer.baseAddress!
                )
            }
        }
    }

    /// MIDI Program Change bytes on channel 0 (status `0xC0`) for a program number,
    /// clamped to the legal 0...127 data range.
    static func programChangeBytes(programNumber: Int) -> [UInt8] {
        let program = UInt8(max(0, min(127, programNumber)))
        return [0xC0, program]
    }

    /// Parses the trailing integer N from a "ProgramChangeN" factory-preset name
    /// (e.g. Arturia Analog Lab V's program-change slots), case-insensitive and
    /// tolerant of surrounding/interstitial whitespace: `^\s*ProgramChange\s*\d+\s*$`.
    ///
    /// Returns N — the AU's own declared program number — for a matching name, or
    /// `nil` for any other name. A `nil` result means "this is a normal preset; do
    /// NOT send a Program Change", which is the key regression guard that keeps the
    /// common AU case (real parameter-state presets) on the `currentPreset =` path.
    static func programNumberFromPresetName(_ name: String) -> Int? {
        let pattern = #"^\s*ProgramChange\s*(\d+)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        guard let match = regex.firstMatch(in: name, options: [], range: range),
              let digitsRange = Range(match.range(at: 1), in: name) else {
            return nil
        }
        return Int(name[digitsRange])
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
    /// `noteOnSampleTime` is the absolute OUTPUT-node render frame the note-on
    /// sounds on — the unified-clock frame
    /// (`AudioMasterClock.sampleTime(atMusicalSeconds:)`) that a slice on this
    /// step also receives. The AU's `scheduleMIDIEventBlock` takes an
    /// `AUEventSampleTime` on the AU's OWN render timeline, which does NOT in
    /// general share a base or rate with the output node (bug 20260630-143852:
    /// an AU with a 44.1 kHz native format in a 48 kHz engine counts its own
    /// frames at 44.1 k — the raw output frame sat ~10 s in the AU's future
    /// after a warm session, silencing the whole first transport run). The host
    /// translates the stamp onto the AU timeline at dispatch via
    /// `auTimelineNoteOnFrame` (see its doc), so the note still lands on the
    /// same INSTANT as the matching slice.
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
                AUNoteTriggerTrace.drop(
                    choice: self.currentChoice.displayName,
                    reason: "instrument-not-loaded",
                    noteCount: noteEvents.count
                )
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
                AUNoteTriggerTrace.drop(
                    choice: self.currentChoice.displayName,
                    reason: "missing-schedule-midi-block",
                    noteCount: noteEvents.count
                )
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
                AUNoteTriggerTrace.drop(
                    choice: self.currentChoice.displayName,
                    reason: "detached-before-schedule",
                    noteCount: noteEvents.count
                )
                return
            }

            // AU-TIMELINE TRANSLATION (bug 20260630-143852 — first-run AU
            // silence, resolved 2026-07-02): the unified-clock note-on frame is
            // an absolute OUTPUT-node render frame, but the AU honours an
            // `AUEventSampleTime` on its OWN render timeline — and the two are
            // NOT the same timebase. The former "HUMAN ACOUSTIC RISK" comment
            // here assumed render-clock base equality; the 2026-07-02 user
            // session disproved it: the AU node (Arturia Jun-6 V, native
            // 44.1 kHz output format behind a converter) advanced its render
            // counter at 44,100 f/s while the output node ran at 48,000 f/s, so
            // after ~112 s of warm session the output-frame stamp sat ~441,000
            // frames (~10 s) in the AU's FUTURE. Every first-run note was
            // scheduled but inaudible until the AU's own counter caught up —
            // right around the user's transport Stop. The fix: translate the
            // stamp through the two "now" values read at dispatch:
            //   auFrame = auNow + (stampOutputFrame − outputNow) · auRate/outRate
            // When the two timelines genuinely coincide (same rate, same base)
            // the translation is the identity, so the offline zero-flam gate's
            // number-equality is preserved; in general the invariant is "same
            // INSTANT", which this translation is what realizes.
            //
            // Past-frame floor (defect D4) is unchanged and now genuinely
            // well-founded: after translation both the stamp and the floor are
            // AU-timeline frames. A stamp already in the AU's past (origin/now
            // skew, late pump wake) is clamped to immediate with a real future
            // note-off. `lastRenderTime` is nil / not-yet-valid before the AU's
            // first render → no floor and no translation base → immediate
            // fallback (same cold behaviour as before).
            let auRenderTime = instrument.lastRenderTime
            let currentRenderFrame: AVAudioFramePosition? =
                (auRenderTime?.isSampleTimeValid == true) ? auRenderTime?.sampleTime : nil
            let auSampleRate: Double = {
                if let auRenderTime, auRenderTime.sampleRate > 0 {
                    return auRenderTime.sampleRate
                }
                let formatRate = instrument.outputFormat(forBus: 0).sampleRate
                return formatRate > 0 ? formatRate : sampleRate
            }()
            // Both "now" values are read here, at dispatch, as close together as
            // the API allows; residual sub-quantum skew between the two last
            // render stamps is caught by the D4 floor.
            let auTimelineNoteOn: AVAudioFramePosition?
            if let noteOnSampleTime,
               let currentRenderFrame,
               let outputNow = self.audioGraph.renderPosition,
               outputNow.sampleRate > 0
            {
                auTimelineNoteOn = Self.auTimelineNoteOnFrame(
                    outputFrame: noteOnSampleTime,
                    outputNowFrame: outputNow.sampleTime,
                    outputSampleRate: outputNow.sampleRate,
                    auNowFrame: currentRenderFrame,
                    auSampleRate: auSampleRate
                )
            } else {
                // No stamp, no AU render base, or no output render position yet:
                // fall back to immediate scheduling (still off-main via the MIDI
                // block), exactly as the pre-translation cold path did.
                auTimelineNoteOn = nil
            }
            var firstScheduledPitch: UInt8?
            var firstScheduledOn: AUEventSampleTime?
            var firstScheduledOff: AUEventSampleTime?
            var gateCount = 0
            for event in noteEvents where event.gate {
                let stamps = Self.noteStamps(
                    noteOnSampleTime: auTimelineNoteOn,
                    length: event.length,
                    bpm: bpm,
                    stepsPerBar: stepsPerBar,
                    sampleRate: auSampleRate,
                    currentRenderFrame: currentRenderFrame
                )
                gateCount += 1
                if firstScheduledPitch == nil {
                    firstScheduledPitch = event.pitch
                    firstScheduledOn = stamps.noteOn
                    firstScheduledOff = stamps.noteOff
                }
                let channel = Self.midiVoiceChannel(
                    forAllocation: self.nextMIDIVoiceChannelIndex
                )
                self.nextMIDIVoiceChannelIndex =
                    (self.nextMIDIVoiceChannelIndex + 1) % Self.midiVoiceChannels.count
                Self.scheduleNote(
                    event,
                    stamps: stamps,
                    channel: channel,
                    using: scheduleMIDI
                )
            }
            let requestedSampleTimeForTrace = noteOnSampleTime.map { Int64($0) }
            let currentRenderFrameForTrace = currentRenderFrame.map { Int64($0) }
            let firstNoteOnForTrace = firstScheduledOn.map { Int64($0) }
            let firstNoteOffForTrace = firstScheduledOff.map { Int64($0) }
            AUNoteTriggerTrace.schedule(
                choice: self.currentChoice.displayName,
                gateCount: gateCount,
                firstPitch: firstScheduledPitch,
                requestedSampleTime: requestedSampleTimeForTrace,
                currentRenderFrame: currentRenderFrameForTrace,
                firstNoteOn: firstNoteOnForTrace,
                firstNoteOff: firstNoteOffForTrace
            )
        }
    }

    /// AU MIDI note-on / note-off bytes on one allocated voice channel. Matching
    /// note-offs stay on that channel, preserving same-pitch overlaps until all
    /// 15 channels are occupied concurrently.
    static func scheduleNote(
        _ event: NoteEvent,
        stamps: AUNoteStamps,
        channel: UInt8,
        using scheduleMIDI: AUScheduleMIDIEventBlock
    ) {
        let velocity = event.velocity
        let pitch = event.pitch
        // Note-on (0x90), then note-off (0x80) one gate-length later, both
        // stamped on the AU render timeline. scheduleMIDIEventBlock copies the
        // bytes synchronously, so a stack array is RT-safe here.
        let noteOn = noteOnBytes(pitch: pitch, velocity: velocity, channel: channel)
        noteOn.withUnsafeBufferPointer { buffer in
            scheduleMIDI(stamps.noteOn, 0, buffer.count, buffer.baseAddress!)
        }
        let noteOff = noteOffBytes(pitch: pitch, channel: channel)
        noteOff.withUnsafeBufferPointer { buffer in
            scheduleMIDI(stamps.noteOff, 0, buffer.count, buffer.baseAddress!)
        }
    }

    private func stopAllNotes() {
        guard let instrument else {
            return
        }

        if let scheduleMIDI = instrument.auAudioUnit.scheduleMIDIEventBlock {
            auMutationLock.lock()
            if self.instrument?.auAudioUnit === instrument.auAudioUnit {
                Self.scheduleAllNotesOff(using: scheduleMIDI)
            }
            auMutationLock.unlock()
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
            for channel in midiVoiceChannels {
                for pitch in UInt8(0)...UInt8(127) {
                    // realtime-allow-control-stopnote: all-notes-off panic on stop/shutdown/preset-silence, NOT the note/tick trigger path (which is sample-stamped via scheduleMIDIEventBlock). Test: RealtimePathLintTests.
                    instrument.stopNote(pitch, onChannel: channel)
                }
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
                self.updateSnapshotOutput()
            }
            if self.audioGraph.engine.outputConnectionPoints(for: nextInstrument, outputBus: 0).isEmpty {
                // realtime-allow-graph-mutation: AU load/setup connection only, not tick dispatch. Test: RealtimePathLintTests.
                self.audioGraph.connect(nextInstrument, to: mixer)
            }
            // A newly-created output mixer may have had no upstream AU input when
            // it was attached. Assert the track's downstream route after AU->mixer
            // is live so AU-only tracks are pulled immediately, not only after a
            // later graph change such as loading a drum kit.
            self.audioGraph.connectTrackOutput(
                mixer,
                to: self.currentOutputBusID,
                sends: self.currentMix.graphSendLevels,
                ramped: false
            )
            self.audioGraph.setTrackMeterSources(trackIDs: self.currentMeterTrackIDs, node: mixer)
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

        rampOutputMixerToSilenceBeforeGraphTeardown(reason: "disconnectCurrentInstrument")
        performOnMain {
            self.log("disconnectCurrentInstrument detach instrument")
            // realtime-allow-graph-mutation: AU destination teardown after outputMixer ramp-to-silence, not tick dispatch. Test: RealtimePathLintTests.
            self.audioGraph.disconnectOutput(instrument)
            // Flush the AU's render state + any note-ON already SCHEDULED
            // (sample-stamped) into its own MIDI queue before the node is
            // detached and the AU deallocated. `stopAllNotes()` above only sends
            // note-OFFs; a queued future note-on is not cancellable via
            // scheduleMIDIEventBlock, so without this reset it can fire into
            // freed sample state on the render thread and crash INSIDE the AU
            // (bug 20260629-121929: SIGSEGV in the AU's own noteOn during
            // remove-while-playing). Output is already disconnected above, so the
            // engine no longer pulls this node when we reset it.
            instrument.auAudioUnit.reset()
            // realtime-allow-graph-mutation: AU destination teardown after outputMixer ramp-to-silence, not tick dispatch. Test: RealtimePathLintTests.
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

    /// Hard Rule 5: before an AU node is disconnected/detached while the engine
    /// may be live, silence the host's output gain stage first. This blocks only
    /// this host's control queue for the short gain dip; it never runs on the
    /// tick/render path and does not hold graph locks while waiting.
    private func rampOutputMixerToSilenceBeforeGraphTeardown(reason: String) {
        guard let outputMixer else { return }

        var shouldRamp = false
        performOnMain {
            shouldRamp = self.audioGraph.isEngineRunning && outputMixer.outputVolume > 0.0005
        }
        guard shouldRamp else { return }

        log("ramp output mixer to silence before graph teardown reason=\(reason)")
        let group = DispatchGroup()
        group.enter()
        performOnMain {
            MixerGainRamp.shared.ramp(outputMixer, to: 0, markSettled: false) { _ in
                group.leave()
            }
        }
        if group.wait(timeout: .now() + 0.2) == .timedOut {
            log("ramp output mixer to silence timed out reason=\(reason)")
        }
    }

    private func startEngineIfPossible() {
        guard autoStartEngine, shouldBeRunning, instrument != nil else {
            return
        }

        log("instrument armed; audio graph lifecycle is session-owned")
    }

    private func applyCurrentMix() {
        guard let outputMixer else {
            return
        }

        let effectivelyMuted = currentMix.isMuted || layerMuteGain
        let targetVolume: Float = effectivelyMuted ? 0 : Float(currentMix.clampedLevel)
        // #58: effective mute must silence the track's ENTIRE contribution,
        // including its Send A/B legs (which tap the fanout downstream of this
        // host's outputMixer but carry their own configured gain). Gate the send
        // legs to 0 while muted; unmute restores the configured send levels.
        let effectiveSendA: Double = effectivelyMuted ? 0 : currentMix.sendA
        let effectiveSendB: Double = effectivelyMuted ? 0 : currentMix.sendB
        performOnMain { [currentMix] in
            outputMixer.pan = Float(currentMix.clampedPan)
            // Mute applies as a short ramped gain (mirrors bus-mute shape) so a
            // ringing AU voice is cut/restored without a click and without
            // waiting for the next trigger.
            MixerGainRamp.shared.ramp(outputMixer, to: targetVolume)
            self.audioGraph.setTrackSendLevels(
                outputMixer,
                sendA: effectiveSendA,
                sendB: effectiveSendB
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
        // Read the output mixer via the snapshot (leaf lock) — NOT a queue/main
        // hop — so a status-writer poll on main can't deadlock against the host
        // queue's AU setup. outputVolume is safe to read off the node directly.
        withSnapshot { snapshotOutputMixer }?.outputVolume
    }

    /// The bus the host has ACTUALLY routed its shared output to (nil = master).
    /// Engine-truth for the gate: set inside `setOutputBusID`, which is the call
    /// that drives the live `connectTrackOutput`. Outer nil = host not loaded.
    func currentOutputBusIDForTesting() -> UUID?? {
        // Read the routing snapshot under the leaf snapshotLock — NOT a
        // `queue.sync` onto the host queue. The host queue runs
        // connectLoadedInstrument -> performOnMain (main.sync) during AU setup,
        // so a main-thread `queue.sync` here is an AB-BA deadlock (it froze the
        // app when the command-channel status writer polled this on main while
        // an AU was instantiating — 2026-06-26). The snapshot is published under
        // the lock on every outputMixer/currentOutputBusID change, so this is
        // torn-read-safe without hopping the queue. Outer nil = host not loaded.
        withSnapshot { snapshotOutputMixer == nil ? UUID??.none : .some(snapshotOutputBusID) }
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

    /// PURE timeline translation (bug 20260630-143852). Maps an absolute
    /// OUTPUT-node render frame onto THIS AU node's OWN render timeline.
    ///
    /// `scheduleMIDIEventBlock` interprets an `AUEventSampleTime` on the AU's
    /// internal render timeline, which is NOT guaranteed to share a base or a
    /// rate with the output node's timeline: an AU whose output format differs
    /// from the engine rate renders behind a converter and counts frames at its
    /// OWN sample rate (measured 2026-07-02: AU at 44,100 f/s vs output at
    /// 48,000 f/s — stamps drifted ~3,900 frames/s into the AU's future, ~10 s
    /// after a ~112 s warm session; first transport run silent, notes fired
    /// after Stop when the AU counter caught up).
    ///
    /// The translation anchors on the two "now" values read at dispatch (the
    /// output node's render position and the AU's `lastRenderTime`), which
    /// describe the same wall-clock instant on the two timelines:
    ///
    ///     auFrame = auNow + (outputFrame − outputNow) × auRate / outputRate
    ///
    /// Identity property: when the two timelines truly coincide (equal rates
    /// AND equal counters — the assumption the old code baked in), this returns
    /// `outputFrame` unchanged, so environments where the old behaviour was
    /// correct are bit-identical. The zero-flam invariant is therefore "same
    /// INSTANT as the matching sample stamp", realized by this translation; it
    /// is numeric equality only in the coinciding-timeline special case.
    static func auTimelineNoteOnFrame(
        outputFrame: AVAudioFramePosition,
        outputNowFrame: AVAudioFramePosition,
        outputSampleRate: Double,
        auNowFrame: AVAudioFramePosition,
        auSampleRate: Double
    ) -> AVAudioFramePosition {
        guard outputSampleRate > 0, auSampleRate > 0 else {
            return outputFrame
        }
        let deltaSeconds = Double(outputFrame - outputNowFrame) / outputSampleRate
        return auNowFrame + AVAudioFramePosition((deltaSeconds * auSampleRate).rounded())
    }

    /// PURE stamp math (Audio Engine Hard Rule 3 / Phase 1 zero-flam gate). No
    /// AU instance, no engine, no clock — fully unit-testable.
    ///
    /// Given the note-on absolute render frame (`noteOnSampleTime`, expressed
    /// ON THE AU'S OWN RENDER TIMELINE — the live path derives it from the
    /// unified-clock frame `AudioMasterClock.sampleTime(atMusicalSeconds:)` via
    /// `auTimelineNoteOnFrame`; when the AU and output timelines coincide the
    /// two are numerically equal) and the per-note gate length, returns the
    /// note-on and note-off `AUEventSampleTime`s on the AU render timeline.
    /// `sampleRate` must likewise be the AU render timeline's rate so the gate
    /// length spans the intended wall-clock duration.
    ///
    /// Zero-flam invariant: `noteStamps(noteOnSampleTime: F, ...).noteOn == F`.
    /// So the AU note-on lands on the EXACT frame requested — the same INSTANT
    /// as the matching slice (the stamp-level zero-flam assertion; the acoustic
    /// level is the human's).
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
    /// pump wake), handing the AU a past frame is undefined/dropped, so the
    /// note-on falls back to immediate while the note-off stays a real future
    /// frame. nil (no render yet) means no floor.
    static func noteStamps(
        noteOnSampleTime: AVAudioFramePosition?,
        length: UInt16,
        bpm: Double,
        stepsPerBar: Int,
        sampleRate: Double,
        currentRenderFrame: AVAudioFramePosition? = nil
    ) -> AUNoteStamps {
        let secondsPerStep = (60.0 / max(bpm, 1)) * (4.0 / Double(max(stepsPerBar, 1)))
        let gateSeconds = secondsPerStep * Double(length)
        let gateFrames = max(1, AVAudioFramePosition((gateSeconds * max(sampleRate, 1)).rounded()))

        guard let noteOnSampleTime, sampleRate > 0 else {
            let noteOff = currentRenderFrame.map { AUEventSampleTime($0 + gateFrames) }
                ?? AUEventSampleTime(gateFrames)
            return AUNoteStamps(
                noteOn: AUEventSampleTime(AUEventSampleTimeImmediate),
                noteOff: noteOff
            )
        }

        // Past-frame guard (D4): a note-on frame already behind the AU's live
        // render position can never sound at that frame. Clamp the note-on to
        // immediate, but preserve the gate with a future note-off so the
        // fallback is audible rather than a zero-duration note.
        if let currentRenderFrame, noteOnSampleTime < currentRenderFrame {
            return AUNoteStamps(
                noteOn: AUEventSampleTime(AUEventSampleTimeImmediate),
                noteOff: AUEventSampleTime(currentRenderFrame + gateFrames)
            )
        }

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

    /// Publish the current output routing into the snapshot. MUST be called on
    /// the host queue right after `outputMixer` / `currentOutputBusID` change, so
    /// the test readouts can read it under `snapshotLock` (a leaf lock) instead
    /// of hopping the host queue.
    private func updateSnapshotOutput() {
        snapshotLock.lock()
        snapshotOutputMixer = outputMixer
        snapshotOutputBusID = currentOutputBusID
        snapshotLock.unlock()
    }
}
