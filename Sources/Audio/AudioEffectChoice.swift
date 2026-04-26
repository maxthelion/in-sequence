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

final class AudioEffectChoiceCache {
    static let shared = AudioEffectChoiceCache()

    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private let maxWaiters = 64
    private var cacheState: CacheState = .idle

    private enum CacheState {
        case idle
        case warming
        case ready([AudioEffectChoice])
    }

    func beginWarmingIfNeeded() {
        lock.lock()
        guard case .idle = cacheState else {
            lock.unlock()
            return
        }
        cacheState = .warming
        lock.unlock()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let choices = self.performScan()
            self.lock.lock()
            self.cacheState = .ready(choices)
            self.lock.unlock()
            for _ in 0..<self.maxWaiters {
                self.semaphore.signal()
            }
        }
    }

    var cachedChoices: [AudioEffectChoice] {
        lock.lock()
        if case let .ready(choices) = cacheState {
            lock.unlock()
            return choices
        }

        let wasIdle: Bool
        if case .idle = cacheState {
            wasIdle = true
            cacheState = .warming
        } else {
            wasIdle = false
        }
        lock.unlock()

        if wasIdle {
            let choices = performScan()
            lock.lock()
            cacheState = .ready(choices)
            lock.unlock()
            for _ in 0..<maxWaiters {
                semaphore.signal()
            }
            return choices
        }

        semaphore.wait()
        semaphore.signal()

        lock.lock()
        if case let .ready(choices) = cacheState {
            lock.unlock()
            return choices
        }
        lock.unlock()
        return []
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
}
