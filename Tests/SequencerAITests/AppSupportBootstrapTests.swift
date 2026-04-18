import XCTest
@testable import SequencerAI

final class AppSupportBootstrapTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("seqai-test-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        if let root = tempRoot {
            try? FileManager.default.removeItem(at: root)
        }
    }

    func test_creates_expected_library_subfolders() throws {
        try AppSupportBootstrap.ensureLibraryStructure(root: tempRoot)

        let expected = [
            "library",
            "library/templates",
            "library/voice-presets",
            "library/fill-presets",
            "library/takes",
            "library/chord-gen-presets",
            "library/slice-sets",
            "library/phrases",
        ]
        for sub in expected {
            let url = tempRoot.appendingPathComponent(sub)
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            XCTAssertTrue(exists, "Missing: \(sub)")
            XCTAssertTrue(isDir.boolValue, "Not a directory: \(sub)")
        }
    }

    func test_idempotent_across_multiple_calls() throws {
        try AppSupportBootstrap.ensureLibraryStructure(root: tempRoot)
        // Calling twice must not throw.
        XCTAssertNoThrow(try AppSupportBootstrap.ensureLibraryStructure(root: tempRoot))
    }

    func test_app_support_root_url_path_contains_bundle_slug() throws {
        let url = try AppSupportBootstrap.appSupportRoot()
        XCTAssertTrue(url.path.contains("sequencer-ai"))
    }
}
