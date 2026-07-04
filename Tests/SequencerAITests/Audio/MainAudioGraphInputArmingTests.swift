import AVFoundation
import AudioToolbox
import XCTest
@testable import SequencerAI

/// Lazy input arming (mic-TCC-at-launch fix).
///
/// AVAudioEngine shares ONE HAL IO unit between input and output. The first
/// `engine.inputNode` access permanently arms `EnableIO` on the unit's input
/// scope, after which EVERY `engine.start()` opens a microphone stream and
/// becomes a mic-TCC trigger. Since the warm-graph change the session graph
/// starts at document open, so any input-side touch on a sample-only session
/// turns into a launch-blocking microphone prompt (ad-hoc rebuilds re-prompt
/// even while the TCC DB still reports `.authorized`).
///
/// These tests pin the invariant: with no armed audio-input routing, the graph
/// performs ZERO `engine.inputNode` accesses and never creates the HAL device
/// owner's input-direction AUHAL.
final class MainAudioGraphInputArmingTests: XCTestCase {
    override func tearDown() {
        MainAudioGraph.liveAudioInputAuthorizedOverrideForTesting = nil
        MainAudioGraph.hardwareInputChannelCountOverrideForTesting = nil
        MainAudioGraph.simulateAudioInputConnectionForTesting = false
        MainAudioGraph.useManualRenderingForAutomation = false
        super.tearDown()
    }

    /// Regression for the record-arm crash (bug 20260702-123512, QA row
    /// 26-audio-recording): under OFFLINE manual rendering (the QA/visual-
    /// automation environment) a stale-authorized TCC record makes
    /// `liveAudioInputAuthorized` true, so a `.input` monitor routing wired
    /// the REAL `engine.inputNode` into an engine that has no input IO unit.
    /// The connect itself held — but tearing that host down (track replace)
    /// and restarting the engine left the input node in the engine's node set
    /// with a NULL AUInterface, and the NEXT running-engine disconnect
    /// (`installMixerBuses` bus-terminal rewire or `repairPreparedTrackGraph`)
    /// made a virtual call through it inside AVFAudio's
    /// `UpdateGraphAfterReconfig` — SIGSEGV at `KERN_INVALID_ADDRESS 0x68`.
    ///
    /// Pins the state invariant behind the fix: an offline manual-rendering
    /// graph must handle the full `.input` install → teardown cycle with ZERO
    /// `engine.inputNode` accesses (the connection is simulated), while the
    /// host still reports a connected input for UI/route state, and a
    /// running-engine disconnect after the teardown must succeed.
    @MainActor
    func test_manualRenderingInputRoutingCycle_neverTouchesInputNode() throws {
        MainAudioGraph.useManualRenderingForAutomation = true
        // The bug's trigger combination: TCC reports authorized (stale record
        // on a rebuilt ad-hoc binary), test-only simulation NOT requested.
        MainAudioGraph.liveAudioInputAuthorizedOverrideForTesting = true
        XCTAssertFalse(MainAudioGraph.simulateAudioInputConnectionForTesting)

        let graph = MainAudioGraph()
        let trackID = UUID()
        let request = MainAudioGraph.AudioInputRoutingRequest(
            trackID: trackID,
            source: .input,
            selectedChannel: .stereo(firstChannel: 0),
            outputBusID: nil,
            mix: .default
        )

        // QA row 25 'live': install the `.input` monitor host.
        graph.syncAudioInputRoutings([request])
        let readout = try XCTUnwrap(graph.audioInputRoutingReadoutForTesting(trackID: trackID))
        XCTAssertEqual(
            readout.connectedSource, .input,
            "host must still report a connected input for UI/route state"
        )
        XCTAssertEqual(
            graph.inputNodeAccessCountForTesting, 0,
            "offline manual-rendering install must never touch engine.inputNode (a dangling input node poisons UpdateGraphAfterReconfig)"
        )

        // QA row 26 (track replace): tear the connected host down.
        graph.syncAudioInputRoutings([])
        XCTAssertEqual(
            graph.inputNodeAccessCountForTesting, 0,
            "teardown of a simulated-input host must not touch engine.inputNode"
        )

        // The next apply's running-engine disconnect — the crash site — must
        // complete. (Offline manual rendering: start() needs no CoreAudio HAL.)
        try graph.start()
        defer { graph.stop() }
        let probe = AVAudioMixerNode()
        graph.attach(probe)
        graph.connect(probe, to: graph.sendReturnDestinationForTesting)
        graph.disconnectOutput(probe)
        graph.detach(probe)
        XCTAssertEqual(graph.inputNodeAccessCountForTesting, 0)
    }

    @MainActor
    func test_constructAndStartWithNoInputRoutings_neverTouchesInputNode() throws {
        let graph = MainAudioGraph()
        XCTAssertEqual(
            graph.inputNodeAccessCountForTesting, 0,
            "graph construction must not touch engine.inputNode"
        )

        do {
            try graph.start()
        } catch {
            throw XCTSkip("CoreAudio engine start is unavailable in this test host: \(error)")
        }
        defer { graph.stop() }

        XCTAssertEqual(
            graph.inputNodeAccessCountForTesting, 0,
            "warm-starting a sample-only graph must not touch engine.inputNode"
        )
        XCTAssertFalse(
            Self.inputScopeEnabled(on: graph.engine),
            "the shared IO unit's input scope must stay disarmed for a sample-only session"
        )
    }

    /// The regression that armed the mic on sample-only launches: a document
    /// containing an (unarmed) audio-input track computes its route state via
    /// `availableInputChannelCount` at document apply. That query used to read
    /// `engine.inputNode.inputFormat(forBus:)` whenever TCC reported
    /// `.authorized` — which is STALE on a rebuilt ad-hoc binary — silently
    /// arming the IO unit's input scope so the warm start prompted at launch.
    /// The channel count must come from HAL property reads instead.
    @MainActor
    func test_availableInputChannelCountQuery_doesNotArmInputNode() throws {
        MainAudioGraph.liveAudioInputAuthorizedOverrideForTesting = true

        let graph = MainAudioGraph()
        _ = graph.availableInputChannelCount

        XCTAssertEqual(
            graph.inputNodeAccessCountForTesting, 0,
            "the channel-count UI affordance must not touch engine.inputNode"
        )
        XCTAssertFalse(
            Self.inputScopeEnabled(on: graph.engine),
            "querying the input channel count must not arm the IO unit's input scope"
        )
    }

    @MainActor
    func test_availableInputChannelCount_respectsAuthorizationAndOverride() {
        let graph = MainAudioGraph()

        MainAudioGraph.liveAudioInputAuthorizedOverrideForTesting = false
        MainAudioGraph.hardwareInputChannelCountOverrideForTesting = 7
        XCTAssertEqual(graph.availableInputChannelCount, 0, "unauthorized input reports zero channels")

        MainAudioGraph.liveAudioInputAuthorizedOverrideForTesting = true
        XCTAssertEqual(graph.availableInputChannelCount, 7, "authorized input reports the hardware count")
        XCTAssertEqual(graph.inputNodeAccessCountForTesting, 0)
    }

    /// Device-preference applies (startup restore, Preferences Apply) must not
    /// reach the HAL input side while no audio-input routing is armed: the
    /// selection is recorded in `deferredInputDeviceUID` instead, and the
    /// owner sees a nil input UID.
    @MainActor
    func test_applyAudioDeviceUIDs_defersInputUntilInputRoutingArmed() throws {
        let owner = RecordingAudioDeviceOwner(activeInputUID: "input-a", activeOutputUID: "output-a")
        let graph = MainAudioGraph()

        let deferred = try graph.applyAudioDeviceUIDs(
            inputUID: "mic-x",
            outputUID: "output-b",
            deviceOwner: owner
        )

        XCTAssertEqual(owner.applyCalls.count, 1)
        XCTAssertNil(owner.applyCalls[0].inputUID, "unarmed session must not forward the input UID to the HAL owner")
        XCTAssertEqual(owner.applyCalls[0].outputUID, "output-b")
        XCTAssertNil(deferred.appliedInputDeviceUID)
        XCTAssertEqual(deferred.deferredInputDeviceUID, "mic-x", "the deferred selection is recorded for persistence")
        XCTAssertEqual(deferred.appliedOutputDeviceUID, "output-b")

        // Arm an audio-input routing (simulated: bookkeeping only, no live
        // inputNode touch) — the same apply now passes the input UID through.
        MainAudioGraph.simulateAudioInputConnectionForTesting = true
        graph.syncAudioInputRoutings([
            MainAudioGraph.AudioInputRoutingRequest(
                trackID: UUID(),
                source: .input,
                selectedChannel: .stereo(firstChannel: 0),
                outputBusID: nil,
                mix: .default
            ),
        ])

        let applied = try graph.applyAudioDeviceUIDs(
            inputUID: "mic-x",
            outputUID: "output-b",
            deviceOwner: owner
        )

        XCTAssertEqual(owner.applyCalls.last?.inputUID, "mic-x", "armed input side applies the selection to the HAL owner")
        XCTAssertEqual(applied.appliedInputDeviceUID, "mic-x")
        XCTAssertNil(applied.deferredInputDeviceUID)
        XCTAssertEqual(graph.inputNodeAccessCountForTesting, 0, "simulated arming performs no real inputNode access")
    }

    /// The real HAL owner must never create its input-direction AUHAL for a
    /// nil input UID (creating + initializing an input-enabled AUHAL is the
    /// mic-TCC trigger in the stored-preference startup path).
    @MainActor
    func test_halDeviceOwner_doesNotCreateInputUnitWithoutExplicitUID() throws {
        let owner = CoreAudioHALDeviceOwner()

        let result = try owner.apply(inputUID: nil, outputUID: nil)

        XCTAssertNil(result.appliedInputDeviceUID)
        XCTAssertFalse(
            owner.hasCreatedInputUnitForTesting,
            "a nil input UID must leave the input-direction AUHAL uncreated"
        )
    }

    private static func inputScopeEnabled(on engine: AVAudioEngine) -> Bool {
        guard let audioUnit = engine.outputNode.audioUnit else { return false }
        var enabled: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioUnitGetProperty(
            audioUnit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Input,
            1,
            &enabled,
            &size
        )
        return status == noErr && enabled != 0
    }
}

private final class RecordingAudioDeviceOwner: AudioDeviceOwning {
    private(set) var applyCalls: [(inputUID: String?, outputUID: String?)] = []
    private var activeInputUID: String?
    private var activeOutputUID: String?

    init(activeInputUID: String?, activeOutputUID: String?) {
        self.activeInputUID = activeInputUID
        self.activeOutputUID = activeOutputUID
    }

    func activeDeviceUID(direction: AudioDeviceDirection) -> String? {
        switch direction {
        case .input: activeInputUID
        case .output: activeOutputUID
        }
    }

    func apply(inputUID: String?, outputUID: String?) throws -> AudioDeviceOwnerApplyResult {
        applyCalls.append((inputUID, outputUID))
        // Mirrors CoreAudioHALDeviceOwner: a nil UID leaves that direction
        // untouched (no unit created / no re-point).
        if let inputUID { activeInputUID = inputUID }
        if let outputUID { activeOutputUID = outputUID }
        return AudioDeviceOwnerApplyResult(
            appliedInputDeviceUID: inputUID != nil ? activeInputUID : nil,
            appliedOutputDeviceUID: outputUID != nil ? activeOutputUID : nil
        )
    }
}
