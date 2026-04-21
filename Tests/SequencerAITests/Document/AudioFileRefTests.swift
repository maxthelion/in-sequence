// Tests/SequencerAITests/Document/AudioFileRefTests.swift
import XCTest
@testable import SequencerAI

final class AudioFileRefTests: XCTestCase {
    func test_appSupportLibrary_codableRoundTrip() throws {
        let ref = AudioFileRef.appSupportLibrary(relativePath: "kick/tr808.wav")
        let data = try JSONEncoder().encode(ref)
        let decoded = try JSONDecoder().decode(AudioFileRef.self, from: data)
        XCTAssertEqual(decoded, ref)
    }

    func test_projectPackage_codableRoundTrip() throws {
        let ref = AudioFileRef.projectPackage(filename: "sample-ABC.wav")
        let data = try JSONEncoder().encode(ref)
        let decoded = try JSONDecoder().decode(AudioFileRef.self, from: data)
        XCTAssertEqual(decoded, ref)
    }

    func test_resolve_appSupport_hit() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let kickDir = tempDir.appendingPathComponent("kick")
        try FileManager.default.createDirectory(at: kickDir, withIntermediateDirectories: true)
        let fileURL = kickDir.appendingPathComponent("tr808.wav")
        try Data().write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let ref = AudioFileRef.appSupportLibrary(relativePath: "kick/tr808.wav")
        let resolved = try ref.resolve(libraryRoot: tempDir)
        XCTAssertEqual(resolved.standardizedFileURL, fileURL.standardizedFileURL)
    }

    func test_resolve_appSupport_missing_throws() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let ref = AudioFileRef.appSupportLibrary(relativePath: "kick/ghost.wav")
        XCTAssertThrowsError(try ref.resolve(libraryRoot: tempDir)) { error in
            XCTAssertEqual(error as? AudioFileRef.ResolveError, .missing)
        }
    }

    func test_resolve_projectPackage_throwsUnsupported() {
        let ref = AudioFileRef.projectPackage(filename: "x.wav")
        XCTAssertThrowsError(try ref.resolve(libraryRoot: URL(fileURLWithPath: "/tmp"))) { error in
            XCTAssertEqual(error as? AudioFileRef.ResolveError, .unsupportedScope)
        }
    }
}
