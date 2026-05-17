import Foundation
import SwiftUI

@MainActor
enum VisualScenarioCommandRunner {
    private static let commandFileEnvironmentKey = "SEQUENCER_AI_VISUAL_COMMAND_FILE"

    static func runIfConfigured(
        section: Binding<WorkspaceSection>,
        session: SequencerDocumentSession,
        engineController: EngineController
    ) async {
        guard let rawPath = ProcessInfo.processInfo.environment[commandFileEnvironmentKey],
              !rawPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        let commandURL = URL(fileURLWithPath: (rawPath as NSString).expandingTildeInPath)
        let statusURL = commandURL.appendingPathExtension("status")
        var lastPayload = ""

        while !Task.isCancelled {
            if let payload = try? String(contentsOf: commandURL), payload != lastPayload {
                lastPayload = payload
                apply(
                    command: parse(payload),
                    section: section,
                    session: session,
                    engineController: engineController
                )
                writeStatus(
                    to: statusURL,
                    section: section.wrappedValue,
                    session: session,
                    engineController: engineController
                )
            }

            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private static func parse(_ payload: String) -> [String: String] {
        payload
            .split(whereSeparator: \.isNewline)
            .reduce(into: [:]) { result, rawLine in
                let line = String(rawLine).trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty, !line.hasPrefix("#"),
                      let separator = line.firstIndex(of: "=")
                else { return }

                let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
                result[key] = value
            }
    }

    private static func apply(
        command: [String: String],
        section: Binding<WorkspaceSection>,
        session: SequencerDocumentSession,
        engineController: EngineController
    ) {
        if let workspace = command["workspace"],
           let requestedSection = WorkspaceSection(rawValue: workspace) {
            section.wrappedValue = requestedSection
        }

        if let gainRaw = command["masterGain"],
           let gain = Double(gainRaw) {
            session.setMasterOutputGain(gain)
            engineController.setLiveMasterOutputGain(gain)
        }

        if let peakRaw = command["meterPeak"],
           let peak = Double(peakRaw) {
            engineController.masterMeterPublisher.recordPeakAmplitudes(left: peak, right: peak)
            engineController.masterMeterPublisher.publishPendingToMain()
        }

        if command["clearClip"] == "true" {
            engineController.masterMeterPublisher.clearClip()
        }

        applySendEffects(command: command, session: session)

        switch command["transport"] {
        case "play":
            engineController.start()
        case "stop":
            engineController.stop()
        default:
            break
        }
    }

    private static func applySendEffects(command: [String: String], session: SequencerDocumentSession) {
        let tracks = session.store.tracks
        for index in tracks.indices {
            let track = tracks[index]
            let sendARaw = command["track\(index)SendA"]
            let sendBRaw = command["track\(index)SendB"]
            guard sendARaw != nil || sendBRaw != nil else { continue }
            session.setTrackSends(
                trackID: track.id,
                sendA: sendARaw.flatMap(Double.init) ?? track.mix.sendA,
                sendB: sendBRaw.flatMap(Double.init) ?? track.mix.sendB
            )
        }

        if let sendAInsert = command["sendAInserts"] {
            session.setSendBusInserts(sendInserts(from: sendAInsert), busID: .sendA)
        }
        if let sendBInsert = command["sendBInserts"] {
            session.setSendBusInserts(sendInserts(from: sendBInsert), busID: .sendB)
        }
    }

    private static func sendInserts(from rawValue: String) -> [SendBusInsert] {
        rawValue
            .split(separator: ",")
            .compactMap { token in
                switch token.trimmingCharacters(in: .whitespacesAndNewlines) {
                case "filter":
                    return .filter()
                case "bitcrusher":
                    return .bitcrusher()
                case "empty", "none", "":
                    return nil
                default:
                    return nil
                }
            }
    }

    private static func writeStatus(
        to statusURL: URL,
        section: WorkspaceSection,
        session: SequencerDocumentSession,
        engineController: EngineController
    ) {
        let meterState = engineController.masterMeterPublisher.displayState
        let status = """
        workspace=\(section.rawValue)
        transport=\(engineController.isRunning ? "play" : "stop")
        masterGain=\(session.store.masterBus.masterOutputGain)
        firstTrackSendA=\(session.store.tracks.first?.mix.sendA ?? 0)
        firstTrackSendB=\(session.store.tracks.first?.mix.sendB ?? 0)
        sendAInsertCount=\(session.store.sendBusA.inserts.count)
        sendBInsertCount=\(session.store.sendBusB.inserts.count)
        clipLatched=\(meterState.isClipLatched)
        clearClipActionable=\(meterState.isClearClipActionable)
        leftPeakDBFS=\(meterState.leftPeakDBFS)
        rightPeakDBFS=\(meterState.rightPeakDBFS)
        """

        try? status.write(to: statusURL, atomically: true, encoding: .utf8)
    }
}
