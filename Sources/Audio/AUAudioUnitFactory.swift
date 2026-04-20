import AudioToolbox
import AVFoundation
import Foundation

final class AUAudioUnitFactory {
    enum FactoryError: Error, Equatable {
        case instantiationFailed(Int32)
        case stateDecodeFailed
    }

    typealias AudioUnitLoader = @Sendable (
        AudioComponentDescription,
        @escaping @Sendable (AVAudioUnit?, Error?) -> Void
    ) -> Void

    private let instantiateAudioUnit: AudioUnitLoader

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

        instantiateAudioUnit(description) { audioUnit, error in
            if let error {
                completion(.failure(.instantiationFailed(Int32((error as NSError).code))))
                return
            }

            guard let audioUnit else {
                completion(.failure(.instantiationFailed(-1)))
                return
            }

            do {
                audioUnit.auAudioUnit.fullState = try FullStateCoder.decode(stateBlob)
                completion(.success(audioUnit))
            } catch {
                completion(.failure(.stateDecodeFailed))
            }
        }
    }

    func captureState(_ unit: AVAudioUnit) throws -> Data? {
        try FullStateCoder.encode(unit.auAudioUnit.fullState)
    }
}
