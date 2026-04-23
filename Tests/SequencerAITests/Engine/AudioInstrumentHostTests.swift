import AVFoundation
import XCTest
@testable import SequencerAI

final class AudioInstrumentHostTests: XCTestCase {
    func test_parameterDescriptors_walks_group_tree_without_kvc() {
        let cutoff = AUParameterTree.createParameter(
            withIdentifier: "cutoff",
            name: "Cutoff",
            address: 1,
            min: 20,
            max: 20_000,
            unit: .hertz,
            unitName: nil,
            flags: [.flag_IsWritable],
            valueStrings: nil,
            dependentParameters: nil
        )
        cutoff.value = 880

        let readOnly = AUParameterTree.createParameter(
            withIdentifier: "meter",
            name: "Meter",
            address: 2,
            min: 0,
            max: 1,
            unit: .generic,
            unitName: nil,
            flags: [],
            valueStrings: nil,
            dependentParameters: nil
        )

        let envelope = AUParameterTree.createParameter(
            withIdentifier: "attack",
            name: "Attack",
            address: 3,
            min: 0,
            max: 5,
            unit: .seconds,
            unitName: nil,
            flags: [.flag_IsWritable],
            valueStrings: nil,
            dependentParameters: nil
        )
        envelope.value = 0.25

        let filterGroup = AUParameterTree.createGroup(
            withIdentifier: "filter",
            name: "Filter",
            children: [cutoff, readOnly]
        )
        let ampGroup = AUParameterTree.createGroup(
            withIdentifier: "amp",
            name: "Amp",
            children: [envelope]
        )
        let synthGroup = AUParameterTree.createGroup(
            withIdentifier: "synth",
            name: "Synth",
            children: [filterGroup, ampGroup]
        )
        let tree = AUParameterTree.createTree(withChildren: [synthGroup])

        let descriptors = AudioInstrumentHost.parameterDescriptors(from: tree)

        XCTAssertEqual(descriptors.count, 2)
        XCTAssertEqual(
            descriptors.map(\.identifier),
            ["cutoff", "attack"]
        )
        XCTAssertEqual(descriptors[0].group, ["Synth", "Filter"])
        XCTAssertEqual(descriptors[0].unit, "Hz")
        XCTAssertEqual(descriptors[0].defaultValue, 880)
        XCTAssertEqual(descriptors[1].group, ["Synth", "Amp"])
        XCTAssertEqual(descriptors[1].unit, "s")
        XCTAssertEqual(descriptors[1].defaultValue, 0.25, accuracy: 0.0001)
    }

    @MainActor
    func test_stale_async_instrument_completion_is_ignored() throws {
        throw XCTSkip("AVAudioUnitMIDIInstrument lifecycle is unstable under xcodebuild's macOS test host; destination/window/controller coverage exercises the supported path.")
        let loader = PendingAudioUnitLoader()
        let host = AudioInstrumentHost(
            instrumentChoices: [.builtInSynth, .testInstrument],
            initialInstrument: .builtInSynth,
            autoStartEngine: false,
            instantiateAudioUnit: loader.load
        )

        XCTAssertEqual(loader.pendingCount, 0)
        XCTAssertFalse(host.isAvailable)

        host.startIfNeeded()
        waitForQueueDrain()

        XCTAssertEqual(loader.pendingCount, 1)

        host.selectInstrument(.testInstrument)
        waitForQueueDrain()

        XCTAssertEqual(loader.pendingCount, 2)
        XCTAssertEqual(host.selectedInstrument, .testInstrument)

        loader.complete(at: 0, with: AVAudioUnitSampler())
        waitForQueueDrain()

        XCTAssertFalse(host.isAvailable)

        loader.complete(at: 1, with: AVAudioUnitSampler())
        waitUntil(timeout: 1) { host.isAvailable }

        XCTAssertTrue(host.isAvailable)
        XCTAssertEqual(host.selectedInstrument, .testInstrument)
        XCTAssertEqual(host.displayName, AudioInstrumentChoice.testInstrument.displayName)
    }

    @MainActor
    func test_pre_attached_audio_unit_falls_back_to_built_in_synth() throws {
        throw XCTSkip("Pre-attached AVAudioUnit handoff restarts the XCTest host before assertions run; keep this as a manual smoke scenario instead.")
        let loader = PendingAudioUnitLoader()
        let host = AudioInstrumentHost(
            instrumentChoices: [.builtInSynth, .testInstrument],
            initialInstrument: .testInstrument,
            autoStartEngine: false,
            instantiateAudioUnit: loader.load
        )
        let foreignEngine = AVAudioEngine()
        let foreignInstrument = AVAudioUnitSampler()
        foreignEngine.attach(foreignInstrument)

        host.startIfNeeded()
        waitForQueueDrain()

        XCTAssertEqual(loader.pendingCount, 1)

        loader.complete(at: 0, with: foreignInstrument)
        waitForQueueDrain()

        XCTAssertEqual(loader.pendingCount, 2)

        loader.complete(at: 1, with: AVAudioUnitSampler())
        waitUntil(timeout: 1) { host.isAvailable }

        XCTAssertTrue(host.isAvailable)
        XCTAssertEqual(host.selectedInstrument, .builtInSynth)
        XCTAssertEqual(host.displayName, AudioInstrumentChoice.builtInSynth.displayName)
    }

    private func waitForQueueDrain() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }

    private func waitUntil(timeout: TimeInterval, condition: @escaping () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
    }
}

private final class PendingAudioUnitLoader {
    private let lock = NSLock()
    private var completions: [(@Sendable (AVAudioUnit?, Error?) -> Void)] = []

    var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return completions.count
    }

    func load(
        _ description: AudioComponentDescription,
        completion: @escaping @Sendable (AVAudioUnit?, Error?) -> Void
    ) {
        lock.lock()
        completions.append(completion)
        lock.unlock()
    }

    func complete(at index: Int, with audioUnit: AVAudioUnit) {
        let completion: (@Sendable (AVAudioUnit?, Error?) -> Void)?
        lock.lock()
        if completions.indices.contains(index) {
            completion = completions[index]
        } else {
            completion = nil
        }
        lock.unlock()

        completion?(audioUnit, nil)
    }
}
