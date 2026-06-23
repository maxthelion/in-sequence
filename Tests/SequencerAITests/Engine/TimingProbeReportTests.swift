import XCTest

final class TimingProbeReportTests: XCTestCase {
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var script: URL {
        repoRoot.appendingPathComponent("scripts/diagnostics/timing-probe-report.sh")
    }

    func test_timingProbeReportSummarizesLateEventsCacheMainHopsAndCorrelations() throws {
        let log = try makeTimingLog("""
        t=100.000 activity name=workspace-mode value=tracks
        t=100.100 sample-cache phase=lookup sample=sample-a track=track-a result=loading durationMs=0.020
        t=100.200 sample-main-hop trackID=track-a reason=repair waitMs=9.250
        t=100.250 graph-repair subsystem=sample track=track-a cause=prepared-track durationMs=3.500 mutations=8
        t=100.300 event-dispatch kind=sample trackID=track-a lateMs=7.500 scheduled=100.292 actual=100.300
        t=103.000 sample-cache phase=load sampleID=sample-a result=ready durationMs=14.200
        """)

        let result = try runReport(arguments: [log.path])

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("sample 1 7.500 7.500"), result.output)
        XCTAssertTrue(result.output.contains("repair 1 9.250 9.250"), result.output)
        XCTAssertTrue(result.output.contains("sample/prepared-track 1 3.500 3.500"), result.output)
        XCTAssertTrue(result.output.contains("loading 1"), result.output)
        XCTAssertTrue(result.output.contains("loading sample=sample-a track=track-a 1"), result.output)
        XCTAssertTrue(result.output.contains("late event preceded by view/activity 1"), result.output)
        XCTAssertTrue(result.output.contains("late event preceded by cache-loading 1"), result.output)
        XCTAssertTrue(result.output.contains("late event preceded by main-hop-repair 1"), result.output)
        XCTAssertTrue(result.output.contains("late event preceded by graph-repair-sample/prepared-track 1"), result.output)
        XCTAssertTrue(result.output.contains("Top remediation suggestions"), result.output)
        XCTAssertTrue(result.output.contains("cache readiness Warm or pin cache entry sample=sample-a track=track-a result=loading"), result.output)
        XCTAssertTrue(result.output.contains("main-hop wait Remove or bound realtime-adjacent main hop reason=repair"), result.output)
        XCTAssertTrue(result.output.contains("graph repair Move graph repair sample/prepared-track out of normal playback"), result.output)
        XCTAssertTrue(result.output.contains("event lateness Investigate sample dispatch scheduling"), result.output)
        XCTAssertTrue(result.output.contains("Failure-threshold late events >= 5ms: 1"), result.output)
    }

    func test_timingProbeReportRanksSuggestionsByObservedImpact() throws {
        let log = try makeTimingLog("""
        t=500.000 sample-cache phase=lookup sample=kick track=drums result=loading durationMs=0.010
        t=500.010 sample-cache phase=lookup sample=kick track=drums result=loading durationMs=0.011
        t=500.020 sample-cache phase=lookup sample=snare track=drums result=hit durationMs=0.012
        t=500.030 sample-main-hop track=drums reason=repair waitMs=9.500
        t=500.040 event-dispatch kind=sample track=drums lateMs=6.000 scheduled=500.034 actual=500.040
        """)

        let result = try runReport(arguments: [log.path])

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("loading sample=kick track=drums 2"), result.output)
        XCTAssertTrue(result.output.contains("hit sample=snare track=drums 1"), result.output)
        guard let firstSuggestion = result.output
            .components(separatedBy: "\n")
            .first(where: { $0.contains("Warm or pin cache entry sample=kick track=drums result=loading") })
        else {
            return XCTFail(result.output)
        }
        XCTAssertTrue(firstSuggestion.hasPrefix("2 cache readiness"), result.output)
    }

    func test_timingProbeReportExitsNonZeroWhenFailureThresholdIsEnabled() throws {
        let log = try makeTimingLog("""
        t=200.000 event-dispatch kind=slice trackID=track-b lateMs=6.250 scheduled=199.994 actual=200.000
        """)

        let result = try runReport(
            arguments: [log.path],
            environment: ["TIMING_PROBE_FAIL_ON_FAILURES": "1"]
        )

        XCTAssertEqual(result.status, 2, result.output)
        XCTAssertTrue(result.output.contains("slice 1 6.250 6.250"), result.output)
        XCTAssertTrue(result.output.contains("Failure-threshold late events >= 5ms: 1"), result.output)
    }

    func test_timingProbeReportSucceedsWhenFailuresStayBelowThreshold() throws {
        let log = try makeTimingLog("""
        t=300.000 event-dispatch kind=midi trackID=track-c lateMs=3.000 scheduled=299.997 actual=300.000
        """)

        let result = try runReport(
            arguments: [log.path],
            environment: ["TIMING_PROBE_FAIL_ON_FAILURES": "1"]
        )

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("midi 1 3.000 3.000"), result.output)
        XCTAssertTrue(result.output.contains("Failure-threshold late events >= 5ms: 0"), result.output)
    }

    func test_timingProbeReportKeepsUiChurnStressGreenBelowFailureThreshold() throws {
        let log = try makeTimingLog("""
        t=600.000 view-switch workspace=tracks tab=tracks mode=setup
        t=600.250 event-dispatch kind=sample trackID=kick lateMs=2.400 scheduled=600.248 actual=600.250
        t=600.900 activity name=workspace-mode from=setup to=perform
        t=601.100 event-dispatch kind=slice trackID=slicer lateMs=4.900 scheduled=601.095 actual=601.100
        t=601.500 view-switch workspace=mixer tab=mixer mode=perform
        t=601.750 event-dispatch kind=sample trackID=snare lateMs=1.500 scheduled=601.749 actual=601.750
        """)

        let result = try runReport(
            arguments: [log.path],
            environment: ["TIMING_PROBE_FAIL_ON_FAILURES": "1"]
        )

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("sample 2 2.400 2.400"), result.output)
        XCTAssertTrue(result.output.contains("slice 1 4.900 4.900"), result.output)
        XCTAssertTrue(result.output.contains("late event preceded by view/activity 2"), result.output)
        XCTAssertTrue(result.output.contains("Failure-threshold late events >= 5ms: 0"), result.output)
    }

    func test_timingProbeReportFailsUiChurnStressWhenEventCrossesFailureThreshold() throws {
        let log = try makeTimingLog("""
        t=700.000 view-switch workspace=tracks tab=tracks mode=setup
        t=700.300 view-switch workspace=phrase tab=layers mode=perform
        t=700.450 event-dispatch kind=sample trackID=kick lateMs=5.500 scheduled=700.444 actual=700.450
        """)

        let result = try runReport(
            arguments: [log.path],
            environment: ["TIMING_PROBE_FAIL_ON_FAILURES": "1"]
        )

        XCTAssertEqual(result.status, 2, result.output)
        XCTAssertTrue(result.output.contains("sample 1 5.500 5.500"), result.output)
        XCTAssertTrue(result.output.contains("late event preceded by view/activity 1"), result.output)
        XCTAssertTrue(result.output.contains("event lateness Investigate sample dispatch scheduling; 1 event(s) exceeded 5ms."), result.output)
        XCTAssertTrue(result.output.contains("Failure-threshold late events >= 5ms: 1"), result.output)
    }

    func test_timingProbeReportTreatsImmediateScheduleLinesAsNonLateContext() throws {
        let log = try makeTimingLog("""
        t=400.000 sample-schedule track=track-a file=kick.wav scheduled=unscheduled actual=400.000 lateMs=0.000000 mode=immediate start=0.000000 length=0.100000 gain=0.000000 startFrame=0 endFrame=4800
        t=400.010 slice-schedule track=track-a file=break.wav scheduled=unscheduled actual=400.010 lateMs=0.000000 mode=immediate startFrame=120 endFrame=480 voiceMode=mono reverse=false choke=true
        """)

        let result = try runReport(
            arguments: [log.path],
            environment: ["TIMING_PROBE_FAIL_ON_FAILURES": "1"]
        )

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("Failure-threshold late events >= 5ms: 0"), result.output)
        XCTAssertFalse(result.output.contains(" -1"), result.output)
    }

    private func makeTimingLog(_ contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("timing-probe-report-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("timing.log")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func runReport(
        arguments: [String],
        environment: [String: String] = [:]
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path] + arguments

        var mergedEnvironment = ProcessInfo.processInfo.environment
        for (key, value) in environment {
            mergedEnvironment[key] = value
        }
        process.environment = mergedEnvironment

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
