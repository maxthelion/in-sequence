import AudioToolbox
import AVFoundation
import Foundation

final class AUAudioUnitFactory {
    enum FactoryError: Error, Equatable {
        case instantiationFailed(domain: String, code: Int, description: String)
        case stateDecodeFailed
    }

    typealias AudioUnitLoader = @Sendable (
        AudioComponentDescription,
        @escaping @Sendable (AVAudioUnit?, Error?) -> Void
    ) -> Void

    private let instantiateAudioUnit: AudioUnitLoader

    private func performOnMain(_ work: @escaping @Sendable () -> Void) {
        if Thread.isMainThread {
            work()
            return
        }

        DispatchQueue.main.async(execute: work)
    }

    init(
        instantiateAudioUnit: @escaping AudioUnitLoader = { description, completion in
            AVAudioUnit.instantiate(
                with: description,
                options: [],
                completionHandler: completion
            )
        }
    ) {
        self.instantiateAudioUnit = instantiateAudioUnit
    }

    func instantiate(
        _ componentID: AudioComponentID,
        stateBlob: Data?,
        completion: @escaping @Sendable (Result<AVAudioUnit, FactoryError>) -> Void
    ) {
        let description = AudioComponentDescription(
            componentType: AudioInstrumentChoice.fourCharCodeValue(componentID.type),
            componentSubType: AudioInstrumentChoice.fourCharCodeValue(componentID.subtype),
            componentManufacturer: AudioInstrumentChoice.fourCharCodeValue(componentID.manufacturer),
            componentFlags: 0,
            componentFlagsMask: 0
        )

        performOnMain { [instantiateAudioUnit] in
            instantiateAudioUnit(description) { audioUnit, error in
                self.performOnMain {
                    if let error {
                        let nsError = error as NSError
                        completion(.failure(.instantiationFailed(
                            domain: nsError.domain,
                            code: nsError.code,
                            description: nsError.localizedDescription
                        )))
                        return
                    }

                    guard let audioUnit else {
                        completion(.failure(.instantiationFailed(
                            domain: "InSequence.AUAudioUnitFactory",
                            code: -1,
                            description: "Audio Unit instantiation returned no unit"
                        )))
                        return
                    }

                    do {
                        if let fullState = try FullStateCoder.decode(stateBlob) {
                            audioUnit.auAudioUnit.fullState = fullState
                        }
                        completion(.success(audioUnit))
                    } catch {
                        completion(.failure(.stateDecodeFailed))
                    }
                }
            }
        }
    }

    func captureState(_ unit: AVAudioUnit) throws -> Data? {
        try FullStateCoder.encode(unit.auAudioUnit.fullState)
    }
}
