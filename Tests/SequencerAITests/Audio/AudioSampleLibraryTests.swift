import XCTest
@testable import SequencerAI

final class AudioSampleLibraryTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempRoot.appendingPathComponent("kick"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempRoot.appendingPathComponent("snare"), withIntermediateDirectories: true)
        try Data().write(to: tempRoot.appendingPathComponent("kick/k-a.wav"))
        try Data().write(to: tempRoot.appendingPathComponent("kick/k-b.wav"))
        try Data().write(to: tempRoot.appendingPathComponent("kick/k-c.wav"))
        try Data().write(to: tempRoot.appendingPathComponent("snare/s-a.wav"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func test_scan_populatesCategoryBuckets() {
        let lib = AudioSampleLibrary(libraryRoot: tempRoot)
        XCTAssertEqual(lib.samples(in: .kick).count, 3)
        XCTAssertEqual(lib.samples(in: .snare).count, 1)
        XCTAssertTrue(lib.samples(in: .hatOpen).isEmpty)
    }

    func test_samples_sortedByFilename() {
        let lib = AudioSampleLibrary(libraryRoot: tempRoot)
        XCTAssertEqual(lib.samples(in: .kick).map(\.name), ["k-a", "k-b", "k-c"])
    }

    func test_ids_stableAcrossRescan() {
        let lib1 = AudioSampleLibrary(libraryRoot: tempRoot)
        let ids1 = lib1.samples(in: .kick).map(\.id)
        let lib2 = AudioSampleLibrary(libraryRoot: tempRoot)
        let ids2 = lib2.samples(in: .kick).map(\.id)
        XCTAssertEqual(ids1, ids2)
    }

    func test_firstSample_returnsFirstInCategory() {
        let lib = AudioSampleLibrary(libraryRoot: tempRoot)
        XCTAssertEqual(lib.firstSample(in: .kick)?.name, "k-a")
        XCTAssertNil(lib.firstSample(in: .hatOpen))
    }

    func test_nextSample_wrapsWithinCategory() {
        let lib = AudioSampleLibrary(libraryRoot: tempRoot)
        let kicks = lib.samples(in: .kick)
        XCTAssertEqual(lib.nextSample(after: kicks[0].id)?.id, kicks[1].id)
        XCTAssertEqual(lib.nextSample(after: kicks[2].id)?.id, kicks[0].id)
    }

    func test_previousSample_wrapsWithinCategory() {
        let lib = AudioSampleLibrary(libraryRoot: tempRoot)
        let kicks = lib.samples(in: .kick)
        XCTAssertEqual(lib.previousSample(before: kicks[0].id)?.id, kicks[2].id)
        XCTAssertEqual(lib.previousSample(before: kicks[1].id)?.id, kicks[0].id)
    }

    func test_unknownCategoryDirectory_getsUnknownCategory() throws {
        try FileManager.default.createDirectory(at: tempRoot.appendingPathComponent("weirdname"), withIntermediateDirectories: true)
        try Data().write(to: tempRoot.appendingPathComponent("weirdname/x.wav"))
        let lib = AudioSampleLibrary(libraryRoot: tempRoot)
        XCTAssertEqual(lib.samples(in: .unknown).count, 1)
    }

    func test_missingRoot_yieldsEmptyLibrary() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("definitely-missing-\(UUID())")
        let lib = AudioSampleLibrary(libraryRoot: missing)
        XCTAssertTrue(lib.samples.isEmpty)
    }

    func test_reload_picksUpNewFile() throws {
        let lib = AudioSampleLibrary(libraryRoot: tempRoot)
        XCTAssertEqual(lib.samples(in: .kick).count, 3)
        try Data().write(to: tempRoot.appendingPathComponent("kick/k-d.wav"))
        lib.reload()
        XCTAssertEqual(lib.samples(in: .kick).count, 4)
    }
}
