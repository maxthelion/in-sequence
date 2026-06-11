import SwiftUI

struct TransportBar: View {
    @Environment(EngineController.self) private var engineController
    @Environment(SequencerDocumentSession.self) private var session
    @State private var phrasePickerPresented = false

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
        HStack(spacing: 10) {
            Button {
                if engineController.isRunning {
                    engineController.stop()
                } else {
                    engineController.start()
                }
            } label: {
                Image(systemName: engineController.isRunning ? "stop.fill" : "play.fill")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(TransportButtonStyle(accent: engineController.isRunning ? StudioTheme.amber : StudioTheme.cyan))
            .disabled(!engineController.canStart)

            Button {} label: {
                Image(systemName: "record.circle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(StudioTheme.amber)
            }
            .buttonStyle(TransportButtonStyle(accent: StudioTheme.amber))
            .disabled(true)

            Rectangle()
                .fill(StudioTheme.border)
                .frame(width: 1, height: 22)

            Text("BPM")
                .studioText(.eyebrow)
                .tracking(0.8)
                .foregroundStyle(StudioTheme.mutedText)
                .lineLimit(1)
                .fixedSize()
                .layoutPriority(2)

            HStack(spacing: 6) {
                // Bold-flat pass: values read in the accent colour.
                Text(String(format: "%.0f", engineController.currentBPM))
                    .studioText(.metricValue)
                    .monospacedDigit()
                    .foregroundStyle(StudioTheme.cyan)
                    .lineLimit(1)
                    .fixedSize()

                StudioStepperButtons(
                    upHelp: "Increase BPM",
                    downHelp: "Decrease BPM",
                    onUp: { stepBPM(by: 1) },
                    onDown: { stepBPM(by: -1) }
                )
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("transport-bpm")
            .layoutPriority(2)

            TransportModePicker(selection: transportModeBinding)
                .layoutPriority(2)

            phraseNavigationControl

            Rectangle()
                .fill(StudioTheme.border)
                .frame(width: 1, height: 22)

            Text(engineController.transportPosition)
                .studioText(.metricValue)
                .monospacedDigit()
                .foregroundStyle(StudioTheme.cyan)
                .lineLimit(1)
                .fixedSize()
                .layoutPriority(2)

            Circle()
                .fill(noteActivityIsHot ? StudioTheme.amber : StudioTheme.mutedText.opacity(0.35))
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .stroke((noteActivityIsHot ? StudioTheme.amber : StudioTheme.border).opacity(0.8), lineWidth: StudioMetrics.borderWidth)
                )
                .animation(.easeOut(duration: 0.12), value: noteActivityIsHot)
                .help(noteActivityIsHot ? "Note triggered" : "No recent note trigger")

            Text(engineController.statusSummary)
                .foregroundStyle(StudioTheme.mutedText)
                .studioText(.label)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(-1)

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(minHeight: 38)
    }

    private func stepBPM(by delta: Double) {
        let next = (engineController.currentBPM + delta).rounded()
        engineController.setBPM(min(300, max(40, next)))
    }

    private var phraseNavigationControl: some View {
        Button {
            phrasePickerPresented.toggle()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: engineController.isRunning && currentPhrase != nil ? "music.note.list" : "music.note")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(currentPhrase == nil ? StudioTheme.mutedText : StudioTheme.cyan)
                    .frame(width: 12)

                Text(phraseControlName)
                    .studioText(.labelBold)
                    .foregroundStyle(currentPhrase == nil ? StudioTheme.mutedText : StudioTheme.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(phraseControlName)
                    .frame(minWidth: 58, maxWidth: 130, alignment: .leading)

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
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .frame(maxWidth: 90)
                    // Colour identifies, it never floods (ux-canon rule 12):
                    // the queued chip stays neutral; amber lives in the
                    // outline and text.
                    .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                            .stroke(StudioTheme.amber.opacity(StudioOpacity.mediumStroke), lineWidth: StudioMetrics.borderWidth)
                    )
                    .help("Queued phrase: \(queuedPhrase.name)")
                    .accessibilityLabel("Queued phrase \(queuedPhrase.name)")
                    .layoutPriority(-1)
                }

                Image(systemName: "square.grid.3x3")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(StudioTheme.mutedText)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .frame(maxWidth: 230, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .fill(Color.white.opacity(StudioOpacity.subtleFill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(currentPhrase == nil ? StudioTheme.border : StudioTheme.cyan.opacity(StudioOpacity.mediumStroke), lineWidth: StudioMetrics.borderWidth)
            )
        }
        .buttonStyle(.plain)
        .disabled(phrases.isEmpty)
        .help(phrases.isEmpty ? "No phrases available" : phraseControlHelp)
        .accessibilityLabel(phraseControlHelp)
        .accessibilityIdentifier("transport-phrase-navigation")
        .sheet(isPresented: $phrasePickerPresented) {
            PhraseLaunchGridSheet(onClose: { phrasePickerPresented = false })
        }
        .onReceive(NotificationCenter.default.publisher(for: .transportPhraseNavigationVisualCommand)) { notification in
            guard let command = notification.object as? String else { return }
            applyVisualPhraseNavigationCommand(command)
        }
        .layoutPriority(1)
    }

    private func phrase(for phraseID: UUID) -> PhraseModel? {
        phrases.first { $0.id == phraseID }
    }

    private func applyVisualPhraseNavigationCommand(_ command: String) {
        switch command {
        case "open":
            if !phrases.isEmpty {
                phrasePickerPresented = true
            }
        case "close":
            phrasePickerPresented = false
        default:
            let parts = command.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  let index = Int(parts[1]),
                  phrases.indices.contains(index)
            else { return }

            let phraseID = phrases[index].id
            switch parts[0] {
            case "queue":
                if session.queuePhrase(phraseID) {
                    phrasePickerPresented = false
                }
            case "now":
                if session.switchPhraseNow(phraseID) {
                    phrasePickerPresented = false
                }
            default:
                break
            }
        }
    }
}

extension Notification.Name {
    static let transportPhraseNavigationVisualCommand = Notification.Name("SequencerAITransportPhraseNavigationVisualCommand")
}


private struct TransportModePicker: View {
    @Binding var selection: TransportMode

    var body: some View {
        HStack(spacing: 4) {
            ForEach(TransportMode.allCases, id: \.self) { mode in
                Button {
                    selection = mode
                } label: {
                    // Bold-flat pass: the selected mode is a solid accent
                    // block with dark text; unselected is outline-only.
                    Text(mode.label)
                        .studioText(.eyebrow)
                        .foregroundStyle(selection == mode ? StudioTheme.background : StudioTheme.mutedText)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(selection == mode ? StudioTheme.amber : Color.clear)
                        )
                        .overlay(
                            Capsule()
                                .stroke(selection == mode ? StudioTheme.amber : StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
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
        // Colour identifies, it never floods (ux-canon rule 12): the button
        // body is a neutral step (brighter while pressed); the accent lives
        // in the outline.
        configuration.label
            .foregroundStyle(StudioTheme.text)
            .frame(width: 34, height: 28)
            .background(Color.white.opacity(configuration.isPressed ? StudioOpacity.borderSubtle : StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                    .stroke(accent.opacity(StudioOpacity.mediumStroke), lineWidth: StudioMetrics.borderWidth)
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
