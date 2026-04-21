import XCTest
import CryptoKit
@testable import SequencerAI

final class SampleLibraryBootstrapTests: XCTestCase {
    private var tempRoot: URL!
    private var source: URL!
    private var destination: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        source = tempRoot.appendingPathComponent("source")
        destination = tempRoot.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func write(_ content: Data, to relativePath: String, under root: URL) throws {
        let fileURL = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: fileURL)
    }

    private func writeManifest(files: [String: String], version: String = "test", under root: URL) throws {
        let manifestURL = root.appendingPathComponent("manifest.json")
        let data = try JSONEncoder().encode(SampleLibraryBootstrap.Manifest(version: version, files: files))
        try data.write(to: manifestURL)
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func test_freshInstall_copiesAllFiles() throws {
        let payload = Data("KICK_1".utf8)
        try write(payload, to: "kick/a.wav", under: source)
        try writeManifest(files: ["kick/a.wav": sha256(payload)], under: source)

        _ = try SampleLibraryBootstrap.ensureLibraryInstalled(
            bundleSamplesURL: source, destinationURL: destination
        )

        let copied = destination.appendingPathComponent("kick/a.wav")
        XCTAssertTrue(FileManager.default.fileExists(atPath: copied.path))
        XCTAssertEqual(try Data(contentsOf: copied), payload)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("manifest.json").path))
    }

    func test_secondRun_isNoOp() throws {
        let payload = Data("SNARE_1".utf8)
        try write(payload, to: "snare/a.wav", under: source)
        try writeManifest(files: ["snare/a.wav": sha256(payload)], under: source)

        _ = try SampleLibraryBootstrap.ensureLibraryInstalled(bundleSamplesURL: source, destinationURL: destination)
        let firstMtime = try FileManager.default.attributesOfItem(atPath: destination.appendingPathComponent("snare/a.wav").path)[.modificationDate] as! Date

        Thread.sleep(forTimeInterval: 1.1)   // ensure mtime would differ if rewritten

        _ = try SampleLibraryBootstrap.ensureLibraryInstalled(bundleSamplesURL: source, destinationURL: destination)
        let secondMtime = try FileManager.default.attributesOfItem(atPath: destination.appendingPathComponent("snare/a.wav").path)[.modificationDate] as! Date

        XCTAssertEqual(firstMtime, secondMtime, "file should not have been rewritten when manifest is identical")
    }

    func test_manifestChange_refreshesChangedFile() throws {
        let v1 = Data("KICK_v1".utf8)
        try write(v1, to: "kick/a.wav", under: source)
        try writeManifest(files: ["kick/a.wav": sha256(v1)], under: source)
        _ = try SampleLibraryBootstrap.ensureLibraryInstalled(bundleSamplesURL: source, destinationURL: destination)

        let v2 = Data("KICK_v2_updated".utf8)
        try write(v2, to: "kick/a.wav", under: source)
        try writeManifest(files: ["kick/a.wav": sha256(v2)], under: source)
        _ = try SampleLibraryBootstrap.ensureLibraryInstalled(bundleSamplesURL: source, destinationURL: destination)

        let dstContent = try Data(contentsOf: destination.appendingPathComponent("kick/a.wav"))
        XCTAssertEqual(dstContent, v2)
    }

    func test_userAddedFile_isPreservedAcrossRefresh() throws {
        let bundleFile = Data("BUNDLED".utf8)
        try write(bundleFile, to: "kick/bundled.wav", under: source)
        try writeManifest(files: ["kick/bundled.wav": sha256(bundleFile)], under: source)
        _ = try SampleLibraryBootstrap.ensureLibraryInstalled(bundleSamplesURL: source, destinationURL: destination)

        let userFile = Data("USER_IMPORTED".utf8)
        try write(userFile, to: "kick/user.wav", under: destination)

        try writeManifest(files: ["kick/bundled.wav": sha256(Data("BUNDLED_v2".utf8))], under: source)
        try write(Data("BUNDLED_v2".utf8), to: "kick/bundled.wav", under: source)
        _ = try SampleLibraryBootstrap.ensureLibraryInstalled(bundleSamplesURL: source, destinationURL: destination)

        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("kick/user.wav")), userFile)
    }

    func test_bundleMissing_createsEmptyDestinationDirectory() throws {
        let missing = tempRoot.appendingPathComponent("does-not-exist")
        let result = try SampleLibraryBootstrap.ensureLibraryInstalled(
            bundleSamplesURL: missing, destinationURL: destination
        )
        XCTAssertEqual(result, destination)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }
}
