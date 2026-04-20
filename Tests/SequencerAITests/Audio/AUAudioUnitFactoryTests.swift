import AVFoundation
import XCTest
@testable import SequencerAI

@MainActor
final class AUAudioUnitFactoryTests: XCTestCase {
    private let appleDLS = AudioComponentID(type: "aumu", subtype: "dls ", manufacturer: "appl", version: 0)

    func test_instantiate_without_stateBlob_succeeds_without_setting_full_state() {
        let sampler = AVAudioUnitSampler()
        let factory = SequencerAI.AUAudioUnitFactory { _, completion in
            completion(sampler, nil)
        }
        let expectation = expectation(description: "factory completion")
        var result: Result<AVAudioUnit, SequencerAI.AUAudioUnitFactory.FactoryError>?

        factory.instantiate(appleDLS, stateBlob: nil) { factoryResult in
            result = factoryResult
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)

        switch result {
        case .success(let unit):
            XCTAssertTrue(unit is AVAudioUnitSampler)
        default:
            XCTFail("Expected instantiation without state blob to succeed.")
        }
    }

    func test_instantiate_with_invalid_stateBlob_fails_state_decode() {
        let sampler = AVAudioUnitSampler()
        let factory = SequencerAI.AUAudioUnitFactory { _, completion in
            completion(sampler, nil)
        }
        let expectation = expectation(description: "factory completion")
        var result: Result<AVAudioUnit, SequencerAI.AUAudioUnitFactory.FactoryError>?

        factory.instantiate(appleDLS, stateBlob: Data("bad-state".utf8)) { factoryResult in
            result = factoryResult
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)

        XCTAssertEqual(result?.failureValue, .stateDecodeFailed)
    }

    func test_instantiate_invokes_loader_on_main_thread() {
        let loaderExpectation = expectation(description: "loader runs on main")
        let completionExpectation = expectation(description: "factory completion")
        let sampler = AVAudioUnitSampler()
        let factory = SequencerAI.AUAudioUnitFactory { _, completion in
            XCTAssertTrue(Thread.isMainThread)
            loaderExpectation.fulfill()
            completion(sampler, nil)
        }

        DispatchQueue.global().async {
            factory.instantiate(self.appleDLS, stateBlob: nil) { _ in
                completionExpectation.fulfill()
            }
        }

        wait(for: [loaderExpectation, completionExpectation], timeout: 1)
    }
}

private extension Result {
    var failureValue: Failure? {
        guard case let .failure(error) = self else {
            return nil
        }
        return error
    }
}
