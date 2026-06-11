import AppKit
import SwiftUI

/// 8×8 phrase launch grid opened from the transport bar. The playing phrase
/// is highlighted with a progress bar showing how far through it is. Clicking
/// a phrase cues it for when the current one finishes; shift-clicking
/// switches to it immediately.
struct PhraseLaunchGridSheet: View {
    @Environment(EngineController.self) private var engineController
    @Environment(SequencerDocumentSession.self) private var session

    let onClose: () -> Void

    private static let columns = 8
    private static let rows = 8
    private static let cellCount = columns * rows

    private var phrases: [PhraseModel] {
        session.store.phrases
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 64, maximum: 140), spacing: 8), count: Self.columns)
    }

    var body: some View {
        StudioModal(
            title: "Phrases",
            subtitle: engineController.isRunning
                ? "Click to cue for the next cycle. Shift-click to switch now."
                : "Click to switch phrase. Playback is stopped.",
            minWidth: 660,
            minHeight: 560,
            onClose: onClose
        ) {
            LazyVGrid(columns: gridColumns, spacing: 8) {
                ForEach(0..<Self.cellCount, id: \.self) { index in
                    if phrases.indices.contains(index) {
                        phraseCell(phrases[index])
                    } else {
                        emptyCell
                    }
                }
            }
        }
        .accessibilityIdentifier("transport-phrase-picker")
    }

    private func phraseCell(_ phrase: PhraseModel) -> some View {
        let isCurrent = engineController.isRunning && phrase.id == engineController.currentPhraseID
        let isQueued = phrase.id == engineController.queuedPhraseID
        let canSwitch = session.canSwitchBasisPhrase(to: phrase.id)

        return Button {
            launch(phrase)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(phrase.name)
                        .studioText(.labelBold)
                        .foregroundStyle(StudioTheme.text)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 0)

                    if isQueued {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(StudioTheme.amber)
                    }
                }

                Text("\(phrase.lengthBars) bar\(phrase.lengthBars == 1 ? "" : "s")")
                    .studioText(.micro)
                    .foregroundStyle(StudioTheme.mutedText)
                    .monospacedDigit()

                Spacer(minLength: 2)

                progressBar(for: phrase, isCurrent: isCurrent)
            }
            .padding(StudioMetrics.Spacing.snug)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
            // Colour identifies, it never floods (ux-canon rule 12): the
            // current phrase reads from the solid cyan outline; the cell body
            // stays on the neutral step.
            .background(
                Color.white.opacity(StudioOpacity.subtleFill),
                in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(
                        isCurrent
                            ? StudioTheme.cyan
                            : (isQueued ? StudioTheme.amber.opacity(StudioOpacity.mediumStroke) : StudioTheme.border),
                        lineWidth: isCurrent ? 2 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canSwitch && !engineController.isRunning)
        .help(helpText(for: phrase, isCurrent: isCurrent, isQueued: isQueued))
        .accessibilityIdentifier("transport-phrase-row-\(phrase.id.uuidString)")
        .accessibilityLabel("\(phrase.name). \(helpText(for: phrase, isCurrent: isCurrent, isQueued: isQueued))")
    }

    @ViewBuilder
    private func progressBar(for phrase: PhraseModel, isCurrent: Bool) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(StudioOpacity.borderFaint))

                if isCurrent {
                    Capsule()
                        .fill(StudioTheme.cyan)
                        .frame(width: geo.size.width * progressFraction(for: phrase))
                }
            }
        }
        .frame(height: 3)
    }

    private func progressFraction(for phrase: PhraseModel) -> CGFloat {
        let playhead = PhrasePlayhead(phrase: phrase, transportTickIndex: engineController.transportTickIndex)
        let total = max(1, phrase.stepCount)
        return CGFloat(playhead.stepIndex + 1) / CGFloat(total)
    }

    private func helpText(for phrase: PhraseModel, isCurrent: Bool, isQueued: Bool) -> String {
        if isCurrent {
            return "Playing now"
        }
        if isQueued {
            return "Queued for the next cycle"
        }
        if engineController.isRunning {
            return "Cue \(phrase.name) for the next cycle. Shift-click to switch now."
        }
        return "Switch to \(phrase.name)"
    }

    private var emptyCell: some View {
        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
            .fill(StudioTheme.inset)
            .frame(minHeight: 62)
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(StudioTheme.border.opacity(0.5), style: StrokeStyle(lineWidth: StudioMetrics.borderWidth, dash: [4, 4]))
            )
    }

    private func launch(_ phrase: PhraseModel) {
        let shiftHeld = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
        if shiftHeld || !engineController.isRunning {
            if session.switchPhraseNow(phrase.id) {
                onClose()
            }
        } else {
            if session.queuePhrase(phrase.id) {
                onClose()
            }
        }
    }
}
