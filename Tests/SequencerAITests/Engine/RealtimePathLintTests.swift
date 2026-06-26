import XCTest

final class RealtimePathLintTests: XCTestCase {
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var script: URL {
        repoRoot.appendingPathComponent("scripts/diagnostics/realtime-path-lint.sh")
    }

    func test_realtimePathLintPasses() throws {
        let result = try runLint()
        XCTAssertEqual(result.status, 0, result.output)
    }

    func test_realtimePathLintFailsOnInjectedAudioFileOpen() throws {
        let fixture = try makeFixture("""
        import AVFoundation
        func dispatchTick() {
            _ = try? AVAudioFile(forReading: URL(fileURLWithPath: "/tmp/kick.wav"))
        }
        """)

        let result = try runLint(arguments: [fixture.path])
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("AVAudioFile(forReading:"), result.output)
    }

    func test_realtimePathLintFailsOnInjectedFileManagerLookup() throws {
        let fixture = try makeFixture("""
        import Foundation
        func enqueueSliceTriggers() {
            _ = FileManager.default.fileExists(atPath: "/tmp/kick.wav")
        }
        """)

        let result = try runLint(arguments: [fixture.path])
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("FileManager.default"), result.output)
    }

    func test_realtimePathLintFailsOnInjectedMainSync() throws {
        let fixture = try makeFixture("""
        import Foundation
        func helper() {
            DispatchQueue.main.sync {}
        }
        """)

        let result = try runLint(arguments: [fixture.path])
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("DispatchQueue.main.sync"), result.output)
    }

    func test_realtimePathLintFailsOnInjectedGraphMutation() throws {
        let fixture = try makeFixture("""
        final class Graph {
            func connect(_ source: Any, to destination: Any) {}
        }
        func dispatchTick(audioGraph: Graph, source: Any, destination: Any) {
            audioGraph.connect(source, to: destination)
        }
        """)

        let result = try runLint(arguments: [fixture.path])
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("audioGraph.connect"), result.output)
    }

    func test_realtimePathLintFailsOnInjectedEngineGraphMutation() throws {
        let fixture = try makeFixture("""
        final class Engine {
            func disconnectNodeOutput(_ node: Any) {}
        }
        func dispatchTick(engine: Engine, node: Any) {
            engine.disconnectNodeOutput(node)
        }
        """)

        let result = try runLint(arguments: [fixture.path])
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("engine.disconnectNodeOutput"), result.output)
    }

    func test_realtimePathLintAllowsGraphMutationInMainAudioGraphOwnerFile() throws {
        let fixture = try makeFixture("""
        final class Engine {
            func connect(_ source: Any, to destination: Any) {}
        }
        final class MainAudioGraph {
            let engine = Engine()
            func reconnect(source: Any, destination: Any) {
                engine.connect(source, to: destination)
            }
        }
        """, fileName: "MainAudioGraph.swift")

        let result = try runLint(arguments: [fixture.path])
        XCTAssertEqual(result.status, 0, result.output)
    }

    func test_realtimePathLintStillRejectsUnannotatedMainSyncInMainAudioGraphOwnerFile() throws {
        let fixture = try makeFixture("""
        import Foundation
        final class Engine {
            func connect(_ source: Any, to destination: Any) {}
        }
        final class MainAudioGraph {
            let engine = Engine()
            func reconnect(source: Any, destination: Any) {
                engine.connect(source, to: destination)
                DispatchQueue.main.sync {}
            }
        }
        """, fileName: "MainAudioGraph.swift")

        let result = try runLint(arguments: [fixture.path])
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("DispatchQueue.main.sync"), result.output)
        XCTAssertFalse(result.output.contains("engine.connect"), result.output)
    }

    func test_realtimePathLintAllowsReasonedGraphMutationAnnotation() throws {
        let fixture = try makeFixture("""
        final class Graph {
            func attach(_ node: Any) {}
        }
        func setup(audioGraph: Graph, node: Any) {
            // realtime-allow-graph-mutation: fixture setup happens before playback dispatch. Test: RealtimePathLintTests.
            audioGraph.attach(node)
        }
        """)

        let result = try runLint(arguments: [fixture.path])
        XCTAssertEqual(result.status, 0, result.output)
    }

    // MARK: - Rule 1 (one audio-derived master clock) — #39

    func test_realtimePathLintFailsOnInjectedWallClockTimingOnTickPath() throws {
        let fixture = try makeFixture("""
        import Foundation
        func prepareTick() -> TimeInterval {
            ProcessInfo.processInfo.systemUptime
        }
        """, fileName: "EngineController.swift")

        let result = try runLint(arguments: [fixture.path])
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("Rule 1"), result.output)
        XCTAssertTrue(result.output.contains("ProcessInfo.processInfo.systemUptime"), result.output)
    }

    func test_realtimePathLintFailsOnInjectedDispatchSourceTimerOnTickPath() throws {
        let fixture = try makeFixture("""
        import Foundation
        var timer: DispatchSourceTimer?
        """, fileName: "TickClock.swift")

        let result = try runLint(arguments: [fixture.path])
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("Rule 1"), result.output)
    }

    func test_realtimePathLintAllowsAnnotatedWallClockTimingOnTickPath() throws {
        let fixture = try makeFixture("""
        import Foundation
        func captureOrigin() -> TimeInterval {
            // realtime-allow-sanctioned-clock: AudioMasterClock pre-render origin fallback. Test: OfflineFrameAccuracyTests.
            ProcessInfo.processInfo.systemUptime
        }
        """, fileName: "EngineController.swift")

        let result = try runLint(arguments: [fixture.path])
        XCTAssertEqual(result.status, 0, result.output)
    }

    func test_realtimePathLintIgnoresWallClockTimingOffTickPath() throws {
        // Rule 1 is scoped to the tick/scheduling-path files only; a wall-clock
        // read in some unrelated file must NOT trip it.
        let fixture = try makeFixture("""
        import Foundation
        func somewhereElse() -> TimeInterval {
            ProcessInfo.processInfo.systemUptime
        }
        """, fileName: "SomeUnrelatedFile.swift")

        let result = try runLint(arguments: [fixture.path])
        XCTAssertEqual(result.status, 0, result.output)
    }

    // MARK: - Rule 4 (resident buffers, no disk on the trigger path) — #39

    func test_realtimePathLintFailsOnInjectedScheduleSegmentInSamplePlaybackEngine() throws {
        let fixture = try makeFixture("""
        import AVFoundation
        func startSliceVoice(_ voice: AVAudioPlayerNode, file: AVAudioFile) {
            voice.scheduleSegment(file, startingFrame: 0, frameCount: 1, at: nil, completionHandler: nil)
        }
        """, fileName: "SamplePlaybackEngine.swift")

        let result = try runLint(arguments: [fixture.path])
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("Rule 4"), result.output)
        XCTAssertTrue(result.output.contains("scheduleSegment"), result.output)
    }

    func test_realtimePathLintAllowsAnnotatedScheduleSegmentInSamplePlaybackEngine() throws {
        let fixture = try makeFixture("""
        import AVFoundation
        func startSliceVoice(_ voice: AVAudioPlayerNode, file: AVAudioFile) {
            // realtime-allow-file-stream: bounded large-loop fallback only. Test: SamplePlaybackEngineResidentBufferTests.
            voice.scheduleSegment(file, startingFrame: 0, frameCount: 1, at: nil, completionHandler: nil)
        }
        """, fileName: "SamplePlaybackEngine.swift")

        let result = try runLint(arguments: [fixture.path])
        XCTAssertEqual(result.status, 0, result.output)
    }

    func test_realtimePathLintIgnoresScheduleSegmentOutsideSamplePlaybackEngine() throws {
        // Rule 4 is scoped to SamplePlaybackEngine.swift; scheduleSegment elsewhere
        // is not the sample-trigger path this rule guards.
        let fixture = try makeFixture("""
        import AVFoundation
        func preview(_ voice: AVAudioPlayerNode, file: AVAudioFile) {
            voice.scheduleSegment(file, startingFrame: 0, frameCount: 1, at: nil, completionHandler: nil)
        }
        """, fileName: "SomeUnrelatedFile.swift")

        let result = try runLint(arguments: [fixture.path])
        XCTAssertEqual(result.status, 0, result.output)
    }

    func test_realtimePathLintRequiresReasonedAllowAnnotation() throws {
        let fixture = try makeFixture("""
        import Foundation
        func helper() {
            // realtime-allow-main-async
            DispatchQueue.main.async {}
        }
        """)

        let result = try runLint(arguments: [fixture.path])
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("allow annotation"), result.output)
    }

    private func makeFixture(_ source: String, fileName: String = "InjectedRealtimePath.swift") throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("realtime-path-lint-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName)
        try source.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func runLint(arguments: [String] = []) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path] + arguments

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        try process.run()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus, text)
    }
}
