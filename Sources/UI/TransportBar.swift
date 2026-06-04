import SwiftUI

struct TransportBar: View {
    @Environment(EngineController.self) private var engineController
    @Environment(SequencerDocumentSession.self) private var session
    @State private var phrasePickerPresented = false

    private var bpmBinding: Binding<Double> {
        Binding(
            get: { engineController.currentBPM },
            set: { engineController.setBPM($0) }
        )
    }

    private var transportModeBinding: Binding<TransportMode> {
        Binding(
            get: { engineController.transportMode },
            set: { engineController.setTransportMode($0) }
        )
    }

    private var noteActivityIsHot: Bool {
        guard engineController.lastNoteTriggerUptime > 0 else {
            return false
        }
        return ProcessInfo.processInfo.systemUptime - engineController.lastNoteTriggerUptime < 0.18
    }

    private var phrases: [PhraseModel] {
        session.store.phrases
    }

    private var currentPhrase: PhraseModel? {
        guard engineController.isRunning,
              let phraseID = engineController.currentPhraseID
        else {
            return nil
        }
        return phrase(for: phraseID)
    }

    private var queuedPhrase: PhraseModel? {
        guard let phraseID = engineController.queuedPhraseID else {
            return nil
        }
        return phrase(for: phraseID)
    }

    private var phraseControlTitle: String {
        if phrases.isEmpty {
            return "NO PHRASES"
        }
        return engineController.isRunning ? "CURRENT PHRASE" : "PHRASE"
    }

    private var phraseControlName: String {
        if let currentPhrase {
            return currentPhrase.name
        }
        if phrases.isEmpty {
            return "Empty"
        }
        return engineController.isRunning ? "No current phrase" : "Stopped"
    }

    private var phraseControlHelp: String {
        var components = [phraseControlTitle.capitalized, phraseControlName]
        if let queuedPhrase {
            components.append("Queued: \(queuedPhrase.name)")
        }
        if !engineController.isRunning {
            components.append("Queueing is available during playback")
        }
        return components.joined(separator: ". ")
    }

    var body: some View {
        HStack(spacing: 14) {
            Button {
                if engineController.isRunning {
                    engineController.stop()
                } else {
                    engineController.start()
                }
            } label: {
                Image(systemName: engineController.isRunning ? "stop.fill" : "play.fill")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(TransportButtonStyle(accent: engineController.isRunning ? StudioTheme.amber : StudioTheme.cyan))
            .disabled(!engineController.canStart)

            Button {} label: {
                Image(systemName: "record.circle.fill")
                    .foregroundStyle(StudioTheme.amber)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(TransportButtonStyle(accent: StudioTheme.amber))
            .disabled(true)

            Rectangle()
                .fill(StudioTheme.border)
                .frame(width: 1, height: 26)

            Text("BPM")
                .studioText(.eyebrow)
                .tracking(0.8)
                .foregroundStyle(StudioTheme.mutedText)

            Slider(value: bpmBinding, in: 40...300)
                .frame(width: 120)
                .tint(StudioTheme.cyan)

            Text(String(format: "%.0f", engineController.currentBPM))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(StudioTheme.text)

            TransportModePicker(selection: transportModeBinding)

            phraseNavigationControl

            Rectangle()
                .fill(StudioTheme.border)
                .frame(width: 1, height: 26)

            Text(engineController.transportPosition)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(StudioTheme.text)

            Circle()
                .fill(noteActivityIsHot ? StudioTheme.amber : StudioTheme.mutedText.opacity(0.35))
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .stroke((noteActivityIsHot ? StudioTheme.amber : StudioTheme.border).opacity(0.8), lineWidth: 1)
                )
                .animation(.easeOut(duration: 0.12), value: noteActivityIsHot)
                .help(noteActivityIsHot ? "Note triggered" : "No recent note trigger")

            Text(engineController.statusSummary)
                .foregroundStyle(StudioTheme.mutedText)
                .studioText(.label)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.035), in: Capsule())
        .overlay(
            Capsule()
                .stroke(StudioTheme.border, lineWidth: 1)
        )
    }

    private var phraseNavigationControl: some View {
        Button {
            phrasePickerPresented.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: engineController.isRunning && currentPhrase != nil ? "music.note.list" : "music.note")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(currentPhrase == nil ? StudioTheme.mutedText : StudioTheme.cyan)
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 2) {
                    Text(phraseControlTitle)
                        .studioText(.microEmphasis)
                        .tracking(0.8)
                        .foregroundStyle(StudioTheme.mutedText)
                        .lineLimit(1)

                    Text(phraseControlName)
                        .studioText(.labelBold)
                        .foregroundStyle(currentPhrase == nil ? StudioTheme.mutedText : StudioTheme.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(phraseControlName)
                }
                .frame(minWidth: 82, maxWidth: 150, alignment: .leading)

                if let queuedPhrase {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 10, weight: .bold))
                        Text(queuedPhrase.name)
                            .studioText(.microEmphasis)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .foregroundStyle(StudioTheme.amber)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .frame(maxWidth: 105)
                    .background(StudioTheme.amber.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                            .stroke(StudioTheme.amber.opacity(StudioOpacity.mediumStroke), lineWidth: 1)
                    )
                    .help("Queued phrase: \(queuedPhrase.name)")
                    .accessibilityLabel("Queued phrase \(queuedPhrase.name)")
                    .layoutPriority(-1)
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(StudioTheme.mutedText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: 290, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .fill(Color.white.opacity(StudioOpacity.subtleFill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(currentPhrase == nil ? StudioTheme.border : StudioTheme.cyan.opacity(StudioOpacity.mediumStroke), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(phrases.isEmpty)
        .help(phrases.isEmpty ? "No phrases available" : phraseControlHelp)
        .accessibilityLabel(phraseControlHelp)
        .accessibilityIdentifier("transport-phrase-navigation")
        .popover(isPresented: $phrasePickerPresented, arrowEdge: .bottom) {
            phrasePicker
        }
        .layoutPriority(1)
    }

    private var phrasePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Phrase Navigation")
                        .studioText(.subtitle)
                        .foregroundStyle(StudioTheme.text)
                    Text(engineController.isRunning ? "Queue at the next cycle or switch now" : "Switch now or start playback before queueing")
                        .studioText(.micro)
                        .foregroundStyle(StudioTheme.mutedText)
                        .lineLimit(1)
                }

                Spacer()
            }

            VStack(spacing: 6) {
                ForEach(phrases) { phrase in
                    PhraseNavigationRow(
                        phrase: phrase,
                        isCurrent: engineController.isRunning && phrase.id == engineController.currentPhraseID,
                        isQueued: phrase.id == engineController.queuedPhraseID,
                        queueEnabled: engineController.isRunning,
                        onQueue: {
                            if engineController.queuePhrase(phrase.id) {
                                phrasePickerPresented = false
                            }
                        },
                        onNow: {
                            if engineController.switchPhraseNow(phrase.id) {
                                phrasePickerPresented = false
                            }
                        }
                    )
                }
            }
        }
        .padding(12)
        .frame(width: 430)
        .background(StudioTheme.stageFill)
        .onExitCommand {
            phrasePickerPresented = false
        }
        .accessibilityIdentifier("transport-phrase-picker")
    }

    private func phrase(for phraseID: UUID) -> PhraseModel? {
        phrases.first { $0.id == phraseID }
    }
}

private struct PhraseNavigationRow: View {
    let phrase: PhraseModel
    let isCurrent: Bool
    let isQueued: Bool
    let queueEnabled: Bool
    let onQueue: () -> Void
    let onNow: () -> Void

    private var statusLabel: String {
        switch (isCurrent, isQueued) {
        case (true, true):
            return "Current and queued"
        case (true, false):
            return "Current"
        case (false, true):
            return "Queued"
        case (false, false):
            return "Available"
        }
    }

    private var queueHelp: String {
        queueEnabled
            ? "Queue \(phrase.name) for the next phrase cycle"
            : "Queueing is available during playback"
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(phrase.name)
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(phrase.name)

                HStack(spacing: 8) {
                    statusBadge(label: statusLabel, systemName: statusSystemName)

                    Text("\(phrase.lengthBars) bar\(phrase.lengthBars == 1 ? "" : "s")")
                        .studioText(.micro)
                        .foregroundStyle(StudioTheme.mutedText)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Queue", action: onQueue)
                .buttonStyle(PhraseActionButtonStyle(accent: StudioTheme.amber))
                .disabled(!queueEnabled)
                .help(queueHelp)
                .accessibilityLabel("Queue \(phrase.name). \(queueHelp)")

            Button("Now", action: onNow)
                .buttonStyle(PhraseActionButtonStyle(accent: StudioTheme.cyan))
                .help("Switch to \(phrase.name) now")
                .accessibilityLabel("Switch to \(phrase.name) now. Switch immediately and clear any queued phrase")
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                .fill(rowFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                .stroke(rowStroke, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("transport-phrase-row-\(phrase.id.uuidString)")
    }

    private var rowFill: Color {
        if isCurrent {
            return StudioTheme.cyan.opacity(StudioOpacity.subtleFill)
        }
        if isQueued {
            return StudioTheme.amber.opacity(StudioOpacity.subtleFill)
        }
        return Color.white.opacity(0.02)
    }

    private var rowStroke: Color {
        if isCurrent {
            return StudioTheme.cyan.opacity(StudioOpacity.mediumStroke)
        }
        if isQueued {
            return StudioTheme.amber.opacity(StudioOpacity.mediumStroke)
        }
        return StudioTheme.border
    }

    private var statusSystemName: String {
        if isCurrent {
            return "checkmark.circle.fill"
        }
        if isQueued {
            return "clock.fill"
        }
        return "circle"
    }

    private func statusBadge(label: String, systemName: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .bold))
            Text(label.uppercased())
                .studioText(.microEmphasis)
                .tracking(0.5)
        }
        .foregroundStyle(isCurrent ? StudioTheme.cyan : (isQueued ? StudioTheme.amber : StudioTheme.mutedText))
        .lineLimit(1)
        .accessibilityLabel(label)
    }
}

private struct PhraseActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .studioText(.eyebrowBold)
            .foregroundStyle(isEnabled ? StudioTheme.text : StudioTheme.mutedText)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(minWidth: 58)
            .background(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                    .fill(isEnabled ? accent.opacity(configuration.isPressed ? 0.26 : 0.14) : Color.white.opacity(0.018))
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                    .stroke(isEnabled ? accent.opacity(StudioOpacity.mediumStroke) : StudioTheme.border, lineWidth: 1)
            )
    }
}

private struct TransportModePicker: View {
    @Binding var selection: TransportMode

    var body: some View {
        HStack(spacing: 4) {
            ForEach(TransportMode.allCases, id: \.self) { mode in
                Button {
                    selection = mode
                } label: {
                    Text(mode.label)
                        .studioText(.eyebrow)
                        .foregroundStyle(selection == mode ? StudioTheme.text : StudioTheme.mutedText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(selection == mode ? StudioTheme.amber.opacity(StudioOpacity.selectedFill) : Color.white.opacity(0.02))
                        )
                        .overlay(
                            Capsule()
                                .stroke(selection == mode ? StudioTheme.amber.opacity(StudioOpacity.mediumStroke) : StudioTheme.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityIdentifier("transport-mode")
    }
}

private struct TransportButtonStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(StudioTheme.text)
            .padding(12)
            .background(accent.opacity(configuration.isPressed ? 0.28 : 0.16), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                    .stroke(accent.opacity(StudioOpacity.mediumStroke), lineWidth: 1)
            )
    }
}

#Preview {
    TransportBarPreview()
}

private struct TransportBarPreview: View {
    @State private var document = SeqAIDocument()

    var body: some View {
        TransportBarPreviewInner(document: $document)
    }
}

private struct TransportBarPreviewInner: View {
    @Binding var document: SeqAIDocument
    @State private var session: SequencerDocumentSession

    init(document: Binding<SeqAIDocument>) {
        self._document = document
        self._session = State(
            initialValue: SequencerDocumentSession(
                document: document,
                engineController: EngineController(client: nil, endpoint: nil)
            )
        )
    }

    var body: some View {
        TransportBar()
            .padding()
            .environment(session.engineController)
            .environment(session)
    }
}
