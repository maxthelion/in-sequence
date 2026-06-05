import XCTest
@testable import SequencerAI

final class PhraseModelPolicyTests: XCTestCase {
    func test_decodeLegacyPhrase_defaultsRepeatAndLoopPolicy() throws {
        let json = """
        {
          "id": "aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb",
          "name": "Legacy",
          "lengthBars": 4,
          "stepsPerBar": 16,
          "cells": []
        }
        """

        let phrase = try JSONDecoder().decode(PhraseModel.self, from: Data(json.utf8))

        XCTAssertEqual(phrase.repeatCount, 1)
        XCTAssertFalse(phrase.loopEnabled)
    }

    func test_decodeClampsPhrasePolicyBounds() throws {
        let json = """
        {
          "id": "aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb",
          "name": "Oversized",
          "lengthBars": 999,
          "stepsPerBar": 0,
          "repeatCount": -12,
          "loopEnabled": true,
          "cells": []
        }
        """

        let phrase = try JSONDecoder().decode(PhraseModel.self, from: Data(json.utf8))

        XCTAssertEqual(phrase.lengthBars, 64)
        XCTAssertEqual(phrase.stepsPerBar, 1)
        XCTAssertEqual(phrase.repeatCount, 0)
        XCTAssertTrue(phrase.loopEnabled)
    }

    func test_modelMutationClampsPhrasePolicyBounds() {
        var phrase = PhraseModel(
            id: UUID(),
            name: "Mutable",
            lengthBars: 8,
            stepsPerBar: 16,
            repeatCount: 1,
            loopEnabled: false,
            cells: []
        )

        phrase.lengthBars = 0
        phrase.repeatCount = 999

        XCTAssertEqual(phrase.lengthBars, 1)
        XCTAssertEqual(phrase.repeatCount, 64)
    }

    func test_codableRoundTripPreservesPhrasePolicy() throws {
        let phrase = PhraseModel(
            id: UUID(),
            name: "Policy",
            lengthBars: 12,
            stepsPerBar: 16,
            repeatCount: 0,
            loopEnabled: true,
            cells: []
        )

        let data = try JSONEncoder().encode(phrase)
        let decoded = try JSONDecoder().decode(PhraseModel.self, from: data)

        XCTAssertEqual(decoded, phrase)
    }
}
