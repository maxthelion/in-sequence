import AVFoundation
import AudioToolbox
import Foundation

struct AudioEffectChoice: Codable, Equatable, Hashable, Identifiable, Sendable {
    let name: String
    let manufacturerName: String
    let componentType: UInt32
    let componentSubType: UInt32
    let componentManufacturer: UInt32

    var id: String {
        "\(componentType)-\(componentSubType)-\(componentManufacturer)-\(name)"
    }

    var displayName: String {
        manufacturerName.isEmpty ? name : "\(manufacturerName) \(name)"
    }

    var componentDescription: AudioComponentDescription {
        AudioComponentDescription(
            componentType: componentType,
            componentSubType: componentSubType,
            componentManufacturer: componentManufacturer,
            componentFlags: 0,
            componentFlagsMask: 0
        )
    }

    var audioComponentID: AudioComponentID {
        AudioComponentID(
            type: AudioInstrumentChoice.fourCharCodeString(componentType),
            subtype: AudioInstrumentChoice.fourCharCodeString(componentSubType),
            manufacturer: AudioInstrumentChoice.fourCharCodeString(componentManufacturer),
            version: 0
        )
    }

    static let testEffect = AudioEffectChoice(
        name: "Test Effect",
        manufacturerName: "Codex",
        componentType: kAudioUnitType_Effect,
        componentSubType: 0x54455354,
        componentManufacturer: 0x43445820
    )

    static var defaultChoices: [AudioEffectChoice] {
        AudioEffectChoiceCache.shared.cachedChoices
    }

    init(
        name: String,
        manufacturerName: String,
        componentType: UInt32,
        componentSubType: UInt32,
        componentManufacturer: UInt32
    ) {
        self.name = name
        self.manufacturerName = manufacturerName
        self.componentType = componentType
        self.componentSubType = componentSubType
        self.componentManufacturer = componentManufacturer
    }

    init(audioComponentID: AudioComponentID, name: String = "External AU Effect", manufacturerName: String = "") {
        self.name = name
        self.manufacturerName = manufacturerName
        self.componentType = AudioInstrumentChoice.fourCharCodeValue(audioComponentID.type)
        self.componentSubType = AudioInstrumentChoice.fourCharCodeValue(audioComponentID.subtype)
        self.componentManufacturer = AudioInstrumentChoice.fourCharCodeValue(audioComponentID.manufacturer)
    }
}

class AudioEffectChoiceCache {
    static let shared = AudioEffectChoiceCache()

    private let condition = NSCondition()
    private var cacheState: CacheState = .idle

    private enum CacheState {
        case idle
        case warming(previous: [AudioEffectChoice]?)
        case ready([AudioEffectChoice])
    }

    func beginWarmingIfNeeded() {
        condition.lock()
        guard case .idle = cacheState else {
            condition.unlock()
            return
        }
        cacheState = .warming(previous: nil)
        condition.unlock()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.completeScan(self.performScan())
        }
    }

    /// Start a refresh on a background queue. Returns `false` if a warm/rescan is already
    /// running, making repeated button presses cheap and safe.
    @discardableResult
    func beginRescanIfNeeded() -> Bool {
        condition.lock()
        let previousChoices: [AudioEffectChoice]?
        switch cacheState {
        case .warming:
            condition.unlock()
            return false
        case .idle:
            previousChoices = nil
        case let .ready(choices):
            previousChoices = choices
        }
        cacheState = .warming(previous: previousChoices)
        condition.unlock()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.completeScan(self.performScan())
        }
        return true
    }

    /// Force a refresh on the caller's thread, waiting for any in-flight scan to finish
    /// first. Intended for off-main rescan coordinators and deterministic tests.
    func rescanChoices() -> [AudioEffectChoice] {
        condition.lock()
        while case .warming = cacheState {
            condition.wait()
        }

        let previousChoices: [AudioEffectChoice]?
        switch cacheState {
        case .idle:
            previousChoices = nil
        case let .ready(choices):
            previousChoices = choices
        case .warming:
            previousChoices = nil
        }
        cacheState = .warming(previous: previousChoices)
        condition.unlock()

        let choices = performScan()
        completeScan(choices)
        return choices
    }

    /// Non-blocking snapshot for UI redraws while a rescan is running.
    var currentChoicesIfAvailable: [AudioEffectChoice]? {
        condition.lock()
        defer { condition.unlock() }
        switch cacheState {
        case .idle:
            return nil
        case let .warming(previous):
            return previous
        case let .ready(choices):
            return choices
        }
    }

    var cachedChoices: [AudioEffectChoice] {
        condition.lock()
        switch cacheState {
        case let .ready(choices):
            condition.unlock()
            return choices
        case .idle:
            cacheState = .warming(previous: nil)
            condition.unlock()
            let choices = performScan()
            completeScan(choices)
            return choices
        case .warming:
            while case .warming = cacheState {
                condition.wait()
            }
            if case let .ready(choices) = cacheState {
                condition.unlock()
                return choices
            }
            condition.unlock()
            return []
        }
    }

    func performScan() -> [AudioEffectChoice] {
        var choices: [AudioEffectChoice] = []
        for componentType in [kAudioUnitType_Effect, kAudioUnitType_MusicEffect] {
            let description = AudioComponentDescription(
                componentType: componentType,
                componentSubType: 0,
                componentManufacturer: 0,
                componentFlags: 0,
                componentFlagsMask: 0
            )
            choices.append(contentsOf: AVAudioUnitComponentManager.shared().components(matching: description).map {
                AudioEffectChoice(
                    name: $0.name,
                    manufacturerName: $0.manufacturerName,
                    componentType: $0.audioComponentDescription.componentType,
                    componentSubType: $0.audioComponentDescription.componentSubType,
                    componentManufacturer: $0.audioComponentDescription.componentManufacturer
                )
            })
        }

#if DEBUG
        if !choices.contains(.testEffect) {
            choices.append(.testEffect)
        }
#endif

        return Array(Set(choices)).sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private func completeScan(_ choices: [AudioEffectChoice]) {
        condition.lock()
        cacheState = .ready(choices)
        condition.broadcast()
        condition.unlock()
    }
}
