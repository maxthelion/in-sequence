import SwiftUI

struct TransportPhraseNavigationPresentation: Equatable {
    var currentName: String
    var currentID: UUID?
    var hasCurrent: Bool
    var nextLabel: String
    var nextName: String
    var nextID: UUID?
    var hasNext: Bool
    var helpText: String

    static func make(
        phrases: [PhraseModel],
        selectedPhraseID: UUID,
        currentPhraseID: UUID?,
        queuedPhraseID: UUID?,
        isRunning: Bool,
        transportMode: TransportMode
    ) -> TransportPhraseNavigationPresentation {
        let selectedPhrase = phrase(id: selectedPhraseID, in: phrases)
        let currentPhrase: PhraseModel?
        if isRunning, let currentPhraseID, let playingPhrase = phrase(id: currentPhraseID, in: phrases) {
            currentPhrase = playingPhrase
        } else {
            currentPhrase = selectedPhrase
        }

        let queuedPhrase = phrase(id: queuedPhraseID, in: phrases)
        let nextPhrase = queuedPhrase ?? arrangementNextPhrase(
            after: currentPhrase,
            phrases: phrases,
            transportMode: transportMode
        )
        let nextLabel = queuedPhrase == nil ? "NEXT" : "QUEUED"
        let currentName = currentPhrase?.name ?? (phrases.isEmpty ? "Empty" : (isRunning ? "No current phrase" : "Stopped"))
        let nextName = nextPhrase?.name ?? "None"

        var helpComponents = ["Current phrase", currentName]
        if let nextPhrase {
            helpComponents.append("\(nextLabel.capitalized): \(nextPhrase.name)")
        } else if transportMode == .free {
            helpComponents.append("No next phrase in Free mode")
        }
        helpComponents.append(isRunning ? "Open the phrase matrix to cue another phrase" : "Open the phrase matrix to switch phrase")

        return TransportPhraseNavigationPresentation(
            currentName: currentName,
            currentID: currentPhrase?.id,
            hasCurrent: currentPhrase != nil,
            nextLabel: nextLabel,
            nextName: nextName,
            nextID: nextPhrase?.id,
            hasNext: nextPhrase != nil,
            helpText: helpComponents.joined(separator: ". ")
        )
    }

    private static func phrase(id: UUID?, in phrases: [PhraseModel]) -> PhraseModel? {
        guard let id else {
            return nil
        }
        return phrases.first { $0.id == id }
    }

    private static func arrangementNextPhrase(
        after currentPhrase: PhraseModel?,
        phrases: [PhraseModel],
        transportMode: TransportMode
    ) -> PhraseModel? {
        guard transportMode == .song,
              let currentPhrase,
              !currentPhrase.loopEnabled,
              currentPhrase.repeatCount != 0,
              phrases.count > 1
        else {
            return nil
        }
        guard let currentIndex = phrases.firstIndex(where: { $0.id == currentPhrase.id }) else {
            return phrases.first
        }
        return phrases[(currentIndex + 1) % phrases.count]
    }
}

struct TransportPhraseProgressPresentation: Equatable {
    var label: String
    var fraction: Double

    static func make(phrase: PhraseModel?, transportTickIndex: UInt64) -> TransportPhraseProgressPresentation {
        guard let phrase else {
            return TransportPhraseProgressPresentation(label: "--", fraction: 0)
        }
        let playhead = PhrasePlayhead(phrase: phrase, transportTickIndex: transportTickIndex)
        let fraction = Double(playhead.stepIndex + 1) / Double(max(1, phrase.stepCount))
        return TransportPhraseProgressPresentation(
            label: "bar \(playhead.barIndex + 1)/\(phrase.lengthBars)",
            fraction: min(max(fraction, 0), 1)
        )
    }
}

enum TransportDocumentEditCommand: CaseIterable {
    case copy
    case paste
    case clearSelection

    var accessibilityLabel: String {
        switch self {
        case .copy: "Copy"
        case .paste: "Paste"
        case .clearSelection: "Clear selection"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .copy: "transport-copy"
        case .paste: "transport-paste"
        case .clearSelection: "transport-clear-selection"
        }
    }

    var helpText: String {
        switch self {
        case .copy: "Copy selection"
        case .paste: "Paste into selection"
        case .clearSelection: "Clear selection"
        }
    }

    var systemImage: String {
        switch self {
        case .copy: "doc.on.doc"
        case .paste: "doc.on.clipboard"
        case .clearSelection: "xmark"
        }
    }

    func isEnabled(in availability: DocumentEditCommandController.Availability) -> Bool {
        switch self {
        case .copy: availability.canCopy
        case .paste: availability.canPaste
        case .clearSelection: availability.canClear
        }
    }

    @MainActor
    @discardableResult
    func perform(on controller: DocumentEditCommandController) -> Bool {
        switch self {
        case .copy: controller.copy()
        case .paste: controller.paste()
        case .clearSelection: controller.clearSelection()
        }
    }
}

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

    private var phrases: [PhraseModel] {
        session.store.phrases
    }

    private var currentPhrase: PhraseModel? {
        if engineController.isRunning,
           let phraseID = engineController.currentPhraseID,
           let phrase = phrase(for: phraseID) {
            return phrase
        }
        return session.store.selectedPhrase
    }

    private var queuedPhrase: PhraseModel? {
        guard let phraseID = engineController.queuedPhraseID else {
            return nil
        }
        return phrase(for: phraseID)
    }

    private var phrasePresentation: TransportPhraseNavigationPresentation {
        TransportPhraseNavigationPresentation.make(
            phrases: phrases,
            selectedPhraseID: session.store.selectedPhraseID,
            currentPhraseID: engineController.currentPhraseID,
            queuedPhraseID: engineController.queuedPhraseID,
            isRunning: engineController.isRunning,
            transportMode: engineController.transportMode
        )
    }

    /// Live scene-crossfader position (0 = scene A, 1 = scene B), or nil when
    /// the master has no A/B scene selection configured (intent 20260629-135428).
    private var sceneCrossfaderValue: Double? {
        guard session.store.masterBus.abSelection != nil else {
            return nil
        }
        return engineController.effectiveCrossfader
    }

    /// Compact read-only transport indicator: scene slots A and B with the
    /// crossfader thumb showing the live x-fader position between them.
    private func sceneCrossfaderIndicator(value: Double) -> some View {
        let clamped = min(max(value, 0), 1)
        let trackWidth: CGFloat = 40
        let thumb: CGFloat = 8
        return HStack(spacing: 6) {
            Text("A")
                .studioText(.eyebrowBold)
                .foregroundStyle(clamped <= 0.5 ? StudioTheme.transportAccent : StudioTheme.mutedText)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(StudioTheme.border)
                    .frame(width: trackWidth, height: 3)
                Circle()
                    .fill(StudioTheme.text)
                    .frame(width: thumb, height: thumb)
                    .offset(x: CGFloat(clamped) * (trackWidth - thumb))
            }
            .frame(width: trackWidth, height: thumb)
            Text("B")
                .studioText(.eyebrowBold)
                .foregroundStyle(clamped >= 0.5 ? StudioTheme.transportAccent : StudioTheme.mutedText)
        }
        .fixedSize()
        .help("Scene crossfader — A \(Int(((1 - clamped) * 100).rounded()))% / B \(Int((clamped * 100).rounded()))%")
        .accessibilityIdentifier("transport-scene-crossfader")
        .accessibilityLabel("Scene crossfader")
        .accessibilityValue("A \(Int(((1 - clamped) * 100).rounded())) percent, B \(Int((clamped * 100).rounded())) percent")
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
            .buttonStyle(TransportButtonStyle(accent: StudioTheme.transportAccent))
            .disabled(!engineController.canStart)

            Button {} label: {
                Image(systemName: "record.circle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(StudioTheme.mutedText)
            }
            .buttonStyle(TransportButtonStyle(accent: StudioTheme.neutral))
            .disabled(true)

            Rectangle()
                .fill(StudioTheme.border)
                .frame(width: 1, height: 22)

            HStack(spacing: 6) {
                // Bold-flat pass: values read in the accent colour. The "BPM"
                // grey label was dropped (bug 20260629-135124) — the value +
                // steppers read as tempo without it.
                Text(String(format: "%.0f", engineController.currentBPM))
                    .studioText(.metricValue)
                    .monospacedDigit()
                    .foregroundStyle(StudioTheme.transportAccent)
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

            HStack(spacing: 6) {
                // Compact swing readout, same treatment as the BPM group (no
                // grey label — the "%" suffix distinguishes it from tempo).
                // 0% = straight, 100% = triplet feel (off-beat 16ths delayed
                // by 1/3 step); see AudioMasterClock.swingMaxStepFraction.
                Text(String(format: "%.0f%%", engineController.currentSwing * 100))
                    .studioText(.metricValue)
                    .monospacedDigit()
                    .foregroundStyle(engineController.currentSwing > 0 ? StudioTheme.transportAccent : StudioTheme.mutedText)
                    .lineLimit(1)
                    .fixedSize()

                StudioStepperButtons(
                    upHelp: "Increase swing",
                    downHelp: "Decrease swing",
                    onUp: { stepSwing(by: 0.05) },
                    onDown: { stepSwing(by: -0.05) }
                )
            }
            .help("Swing — delays every off-beat 16th step (100% = triplet feel)")
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Swing")
            .accessibilityValue("\(Int((engineController.currentSwing * 100).rounded())) percent")
            .accessibilityIdentifier("transport-swing")
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
                .foregroundStyle(StudioTheme.transportAccent)
                .lineLimit(1)
                .fixedSize()
                .layoutPriority(2)

            documentEditCommands

            if let crossfader = sceneCrossfaderValue {
                sceneCrossfaderIndicator(value: crossfader)
            }

            Spacer()
        }
        // Tighter left gap + a taller bar (bug 20260629-135124).
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .padding(.vertical, 7)
        .frame(minHeight: 46)
    }

    private var documentEditCommands: some View {
        let controller = session.documentEditCommands
        let availability = controller.availability
        return HStack(spacing: 4) {
            ForEach(TransportDocumentEditCommand.allCases, id: \.self) { command in
                Button {
                    command.perform(on: controller)
                } label: {
                    Image(systemName: command.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(TransportButtonStyle(accent: StudioTheme.neutral))
                .disabled(!command.isEnabled(in: availability))
                .help(command.helpText)
                .accessibilityLabel(command.accessibilityLabel)
                .accessibilityIdentifier(command.accessibilityIdentifier)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("transport-document-edit-commands")
    }

    private func stepBPM(by delta: Double) {
        let next = (engineController.currentBPM + delta).rounded()
        engineController.setBPM(min(300, max(40, next)))
    }

    private func stepSwing(by delta: Double) {
        // Round to the 5% grid so repeated stepping never accumulates drift.
        let next = ((engineController.currentSwing + delta) * 20).rounded() / 20
        engineController.setSwing(min(1, max(0, next)))
    }

    private var phraseNavigationControl: some View {
        HStack(spacing: 6) {
            // CURRENT phrase button: tap opens the phrase; embedded matrix icon
            // opens the launch grid to schedule a new phrase; a thin progress
            // bar runs along the bottom (no text).
            phraseButton(
                title: phrasePresentation.currentName,
                accent: StudioTheme.transportAccent,
                isPrimary: phrasePresentation.hasCurrent,
                openPhraseID: phrasePresentation.currentID,
                showProgress: true
            )

            // Chevron conveys "current → next".
            Image(systemName: "chevron.compact.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(StudioTheme.mutedText)
                .accessibilityHidden(true)

            // NEXT / QUEUED phrase button.
            phraseButton(
                title: phrasePresentation.nextName,
                accent: phrasePresentation.hasNext ? StudioTheme.transportAccent : StudioTheme.border,
                isPrimary: phrasePresentation.hasNext,
                openPhraseID: phrasePresentation.nextID,
                showProgress: false
            )
        }
        .help(phrases.isEmpty ? "No phrases available" : phrasePresentation.helpText)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(phrasePresentation.helpText)
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

    private func phraseButton(
        title: String,
        accent: Color,
        isPrimary: Bool,
        openPhraseID: UUID?,
        showProgress: Bool
    ) -> some View {
        // Tapping the body opens the phrase; the trailing matrix icon is a
        // separate tap target that opens the launch grid for scheduling.
        Button {
            if let openPhraseID {
                session.setSelectedPhraseID(openPhraseID)
            } else if !phrases.isEmpty {
                phrasePickerPresented = true
            }
        } label: {
            HStack(spacing: 5) {
                Text(title)
                    .studioText(.microEmphasis)
                    .foregroundStyle(isPrimary ? StudioTheme.text : StudioTheme.mutedText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                // Matrix icon: schedule a new phrase in this slot.
                Button {
                    if !phrases.isEmpty {
                        phrasePickerPresented = true
                    }
                } label: {
                    Image(systemName: "square.grid.3x3")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(StudioTheme.mutedText)
                }
                .buttonStyle(.plain)
                .disabled(phrases.isEmpty)
                .help("Schedule a phrase")
                .accessibilityLabel("Schedule a phrase")
            }
            .frame(width: 96, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, 5)
            .padding(.bottom, showProgress ? 6 : 5)
            .background(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .fill(StudioTheme.subtleFill)
            )
            .overlay(alignment: .bottom) {
                if showProgress {
                    TransportPhraseProgressBar(phrase: currentPhrase)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 3)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(isPrimary ? accent.opacity(StudioOpacity.mediumStroke) : StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
            )
            .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(phrases.isEmpty)
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

private struct TransportPhraseProgressBar: View {
    @Environment(EngineController.self) private var engineController
    let phrase: PhraseModel?

    var body: some View {
        // One presentation per render — this is a transport-tick-rate leaf, so
        // make() ran up to 3× per frame when split across two computed props.
        let progress = TransportPhraseProgressPresentation.make(
            phrase: phrase,
            transportTickIndex: engineController.transportTickIndex
        )
        // Thin progress bar along the bottom of the current-phrase button — no
        // accompanying "bar x/y" text per the rework.
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(StudioTheme.borderFaintFill)

                Capsule()
                    .fill(phrase == nil ? StudioTheme.border : StudioTheme.transportAccent)
                    .frame(width: geo.size.width * CGFloat(progress.fraction))
            }
        }
        .frame(height: 3)
        .accessibilityLabel("Phrase progress \(progress.label)")
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
                                .fill(selection == mode ? StudioTheme.transportAccent : Color.clear)
                        )
                        .overlay(
                            Capsule()
                                .stroke(selection == mode ? StudioTheme.transportAccent : StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
                        )
                        // Unselected modes have a clear fill; pin the hit area to
                        // the whole capsule so taps don't require the glyph.
                        .contentShape(Capsule())
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
            .background(configuration.isPressed ? StudioTheme.borderSubtleFill : StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                    .stroke(accent.opacity(StudioOpacity.mediumStroke), lineWidth: StudioMetrics.borderWidth)
            )
            // The glyph alone is a small target; make the whole tile tappable.
            .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous))
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
