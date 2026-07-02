import XCTest
@testable import SequencerAI

final class LibraryAssetCatalogTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func makeCatalog() -> LibraryAssetCatalog {
        LibraryAssetCatalog(
            sampleLibrary: AudioSampleLibrary(libraryRoot: tempRoot),
            drumAssetLibrary: DrumAssetLibrary(libraryRoot: tempRoot),
            recordingLibrary: RecordingLibrary(libraryRoot: tempRoot)
        )
    }

    // MARK: - Missing assets render as marked entries, never raw IDs

    func test_missingPooledAssets_resolveAsMissingWithoutRawIDs() {
        let catalog = makeCatalog()
        let refs: [PooledAssetRef] = PooledAssetKind.allCases.map {
            PooledAssetRef(kind: $0, assetID: UUID())
        }

        for resolved in catalog.resolveAll(refs) {
            XCTAssertTrue(resolved.isMissing, "\(resolved.ref.kind) should resolve missing")
            XCTAssertNil(resolved.revealCategory)
            XCTAssertFalse(
                resolved.name.contains(resolved.ref.assetID.uuidString),
                "raw IDs must never be user-facing labels"
            )
            XCTAssertFalse(resolved.name.isEmpty)
        }
    }

    func test_factoryKitAndTemplate_resolveWithFactsAndRevealCategory() {
        let catalog = makeCatalog()
        let kit = DrumAssetLibrary.factoryKits[0]
        let template = DrumAssetLibrary.factoryTemplates[0]

        let kitEntry = catalog.resolve(PooledAssetRef(kind: .drumKit, assetID: kit.id))
        XCTAssertFalse(kitEntry.isMissing)
        XCTAssertEqual(kitEntry.name, kit.name)
        XCTAssertEqual(kitEntry.facts, "\(kit.parts.count) parts")
        XCTAssertEqual(kitEntry.revealCategory, .drumKits)

        let templateEntry = catalog.resolve(PooledAssetRef(kind: .patternTemplate, assetID: template.id))
        XCTAssertFalse(templateEntry.isMissing)
        XCTAssertEqual(templateEntry.revealCategory, .patternTemplates)
    }

    func test_storedRecording_resolvesFromPoolAndListsInRecordingsCategory() throws {
        let recordingLibrary = RecordingLibrary(libraryRoot: tempRoot)
        let pcm = AudioInputCapturedPCM(
            sampleRate: 44_100,
            channels: [(0..<441).map { _ in Float(0.25) }]
        )
        let asset = try recordingLibrary.storeRecording(pcm: pcm, sourceTrackName: "Mic", barCount: 2, bpm: 130)

        let catalog = LibraryAssetCatalog(
            sampleLibrary: AudioSampleLibrary(libraryRoot: tempRoot),
            drumAssetLibrary: DrumAssetLibrary(libraryRoot: tempRoot),
            recordingLibrary: recordingLibrary
        )

        let entries = catalog.entries(in: .recordings)
        XCTAssertEqual(entries.map(\.assetID), [asset.id])
        XCTAssertEqual(entries.first?.poolKind, .sample)
        XCTAssertNotNil(entries.first?.auditionURL)
        XCTAssertEqual(entries.first?.facts, "2 bars · 0.01s · 130 BPM")

        let resolved = catalog.resolve(PooledAssetRef(kind: .sample, assetID: asset.id))
        XCTAssertFalse(resolved.isMissing)
        XCTAssertEqual(resolved.name, asset.name)
        XCTAssertEqual(resolved.revealCategory, .recordings)
    }

    func test_categoryRawValues_bridgeToSampleCategories() {
        XCTAssertEqual(LibraryCategory.breaks.sampleCategory, .breaks)
        XCTAssertEqual(LibraryCategory.recordings.sampleCategory, .recordings)
        XCTAssertEqual(LibraryCategory.hatClosed.sampleCategory, .hatClosed)
        XCTAssertNil(LibraryCategory.drumKits.sampleCategory)
        XCTAssertNil(LibraryCategory.patternTemplates.sampleCategory)
        XCTAssertNil(LibraryCategory.stepOrderMaps.sampleCategory)
        XCTAssertNil(LibraryCategory.auInstruments.sampleCategory)
        XCTAssertNil(LibraryCategory.generators.sampleCategory)
    }

    /// AU instruments and generators are browsable categories but not
    /// pool-backed assets: the catalog resolves them to NO entries (the
    /// Library page renders their rows from the live component scan / project
    /// pool instead), and they carry real display names.
    func test_auInstrumentsAndGenerators_areNotCatalogResolved() {
        let catalog = makeCatalog()
        XCTAssertTrue(catalog.entries(in: .auInstruments).isEmpty)
        XCTAssertTrue(catalog.entries(in: .generators).isEmpty)
        XCTAssertEqual(LibraryCategory.auInstruments.displayName, "AU Instruments")
        XCTAssertEqual(LibraryCategory.generators.displayName, "Generators")
    }

    func test_emptyLibraries_produceEmptyCategoriesWithoutCrashing() {
        let catalog = makeCatalog()
        for category in LibraryAssetCatalog.categories where category != .drumKits && category != .patternTemplates {
            XCTAssertTrue(catalog.entries(in: category).isEmpty, "\(category) should be empty")
        }
        // Factory content keeps kits/templates populated even with no user files.
        XCTAssertEqual(catalog.entryCount(in: .drumKits), 3)
        XCTAssertEqual(catalog.entryCount(in: .patternTemplates), 3)
    }
}
