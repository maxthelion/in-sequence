import XCTest
@testable import SequencerAI

final class AudioSampleTests: XCTestCase {
    func test_equality_sameFieldsAreEqual() {
        let id = UUID()
        let ref = AudioFileRef.appSupportLibrary(relativePath: "kick/a.wav")
        let a = AudioSample(id: id, name: "a", fileRef: ref, category: .kick, lengthSeconds: 0.5)
        let b = AudioSample(id: id, name: "a", fileRef: ref, category: .kick, lengthSeconds: 0.5)
        XCTAssertEqual(a, b)
    }

    func test_hashable_usesID() {
        let shared = UUID()
        let a = AudioSample(id: shared, name: "a", fileRef: .appSupportLibrary(relativePath: "k/a.wav"), category: .kick, lengthSeconds: 0.5)
        let b = AudioSample(id: shared, name: "b-different-name", fileRef: .appSupportLibrary(relativePath: "k/b.wav"), category: .snare, lengthSeconds: 0.3)
        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(a.hashValue, b.hashValue)
    }
}
