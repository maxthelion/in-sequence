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

    /// Compact scene-perform launcher. The miniature crossfader preserves the
    /// live A/B position while the whole control opens Phrase > Scenes.
    private func sceneCrossfaderButton(value: Double) -> some View {
        let clamped = min(max(value, 0), 1)
        let trackWidth: CGFloat = 40
        let thumbWidth: CGFloat = 10
        let thumbHeight: CGFloat = 8
        let aPercent = Int(((1 - clamped) * 100).rounded())
        let bPercent = Int((clamped * 100).rounded())
        return Button {
            session.requestScenePerform()
        } label: {
            HStack(spacing: 6) {
                Text("A")
                    .studioText(.eyebrowBold)
                    .foregroundStyle(clamped <= 0.5 ? StudioTheme.transportAccent : StudioTheme.mutedText)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.mini, style: .continuous)
                        .fill(StudioTheme.border)
                        .frame(width: trackWidth, height: 3)
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.mini, style: .continuous)
                        .fill(StudioTheme.text)
                        .frame(width: thumbWidth, height: thumbHeight)
                        .offset(x: CGFloat(clamped) * (trackWidth - thumbWidth))
                }
                .frame(width: trackWidth, height: thumbHeight)
                Text("B")
                    .studioText(.eyebrowBold)
                    .foregroundStyle(clamped >= 0.5 ? StudioTheme.transportAccent : StudioTheme.mutedText)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(
                StudioTheme.subtleFill,
                in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                    .stroke(StudioTheme.transportAccent.opacity(StudioOpacity.mediumStroke), lineWidth: StudioMetrics.borderWidth)
            )
            .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("Open scene perform — A \(aPercent)% / B \(bPercent)%")
        .accessibilityIdentifier("transport-scene-crossfader")
        .accessibilityLabel("Open scene perform")
        .accessibilityValue("A \(aPercent) percent, B \(bPercent) percent")
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

            transportModeControl
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
                sceneCrossfaderButton(value: crossfader)
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

    private var transportModeControl: some View {
        StudioSegmentedControl(
            title: nil,
            selection: transportModeBinding,
            segments: TransportMode.allCases.map { mode in
                StudioSegment(
                    title: mode.label,
                    value: mode,
                    accessibilityIdentifier: "transport-mode-\(mode.label.lowercased())",
                    accessibilityLabel: "Transport mode \(mode.label)"
                )
            },
            accent: StudioTheme.transportAccent,
            layout: StudioSegmentedControl.Layout(
                fillsWidth: false,
                minWidth: 42,
                minHeight: 22,
                horizontalPadding: 6,
                minimumScaleFactor: nil
            )
        )
        .accessibilityIdentifier("transport-mode")
    }

    private var phraseNavigationControl: some View {
        Button {
            if !phrases.isEmpty {
                phrasePickerPresented = true
            }
        } label: {
            StudioDisclosureLabel(
                title: phrasePresentation.currentName,
                detail: phrasePresentation.nextName,
                symbolName: "square.grid.3x3",
                relationshipSymbolName: phrasePresentation.nextLabel == "QUEUED"
                    ? "clock.fill"
                    : "chevron.compact.right",
                minimumWidth: 196
            )
            .overlay(alignment: .bottomLeading) {
                if phrasePresentation.hasCurrent {
                    TransportPhraseProgressBar(phrase: currentPhrase)
                        .frame(width: 72)
                        .padding(.leading, 29)
                        .padding(.bottom, 3)
                }
            }
        }
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(phrases.isEmpty)
        .help(phrases.isEmpty ? "No phrases available" : phrasePresentation.helpText)
        .accessibilityLabel(phrasePresentation.helpText)
        .accessibilityIdentifier("transport-phrase-navigation")
        .sheet(isPresented: $phrasePickerPresented) {
            PhraseLaunchGridSheet(onClose: { phrasePickerPresented = false })
        }
        .onReceive(NotificationCenter.default.publisher(for: .transportPhraseNavigationVisualCommand)) { notification in
            guard let command = notification.object as? String else { return }
            applyVisualPhraseNavigationCommand(command)
        }
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
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.mini, style: .continuous)
                    .fill(StudioTheme.borderFaintFill)

                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.mini, style: .continuous)
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


private struct TransportButtonStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        // Colour identifies, it never floods (ux-canon rule 12): the button
        // body is a neutral step (brighter while pressed); the accent lives
        // in the outline.
        configuration.label
            .foregroundStyle(StudioTheme.text)
            .frame(width: 34, height: 28)
            .background(configuration.isPressed ? StudioTheme.borderSubtleFill : StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                    .stroke(accent.opacity(StudioOpacity.mediumStroke), lineWidth: StudioMetrics.borderWidth)
            )
            // The glyph alone is a small target; make the whole tile tappable.
            .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
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
