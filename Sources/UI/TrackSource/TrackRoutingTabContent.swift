import SwiftUI

/// The ROUTING tab body: the whole audio path in one place.
///
/// `INSTRUMENT (read-only summary) → FX chain / instrument params →
/// DESTINATION (master / a bus) + sends A/B`. This is a RE-HOME of the
/// (previously permanent right-hand) destination column into a tab plus a
/// one-glance path summary — it reuses the existing destination-editing
/// controls (`TrackDestinationEditor`) and the existing send/route model
/// (`session.setTrackOutputBus` / `session.setTrackMix`). No new routing
/// semantics are introduced here.
///
/// The in-place macro-assign affordance ("◎" in the wireframe) is the
/// existing AU macro-slot assignment surfaced by `TrackDestinationEditor`'s
/// AU editor (`AUMacroSlotKnob` → `SingleMacroSlotPickerSheet` →
/// `session.assignAUMacroToSlot`). The DEFERRED global macro rack is not
/// built here; assignment registers against the existing per-track macro
/// bindings, which already feed the macro layer model.
struct TrackRoutingTabContent: View {
    enum Mode {
        case sound
        case mixer
    }

    @Binding var document: SeqAIDocument
    @Environment(SequencerDocumentSession.self) private var session
    let summary: TrackRoutingPathSummary
    let mode: Mode
    let accent: Color

    private var track: StepSequenceTrack { session.store.selectedTrack }
    private var buses: [MixerBus] { session.store.buses }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch mode {
            case .sound:
                soundSourceWell
            case .mixer:
                mixerWell
            }
        }
        .padding(StudioMetrics.Spacing.standard)
    }

    private var soundSourceWell: some View {
        TrackDestinationEditor(document: $document)
    }

    private var mixerWell: some View {
        VStack(alignment: .leading, spacing: 14) {
            pathSummaryHeader
            destinationRow
        }
    }

    // MARK: - Path summary (INSTRUMENT → FX → DEST)

    private var pathSummaryHeader: some View {
        HStack(spacing: 10) {
            pathChip(eyebrow: "Instrument", value: summary.instrumentLabel)

            pathArrow

            pathChip(eyebrow: "Destination", value: summary.destinationLabel, detail: summary.sendsSummary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pathChip(eyebrow: String, value: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(eyebrow.uppercased())
                .studioText(.eyebrow)
                .tracking(0.8)
                .foregroundStyle(StudioTheme.mutedText)
            Text(value)
                .studioText(.labelBold)
                .foregroundStyle(StudioTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let detail {
                Text(detail)
                    .studioText(.micro)
                    .foregroundStyle(StudioTheme.mutedText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
        )
    }

    private var pathArrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(StudioTheme.mutedText)
    }

    // MARK: - Destination + sends (master / a bus, sends A/B)

    private var destinationRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MIXER & FX")
                .studioText(.eyebrow)
                .tracking(0.8)
                .foregroundStyle(StudioTheme.mutedText)

            HStack(alignment: .center, spacing: 16) {
                outputSelector
                Spacer(minLength: 12)
                sendKnob(.a, value: summary.sendA)
                sendKnob(.b, value: summary.sendB)
            }
        }
        .padding(StudioMetrics.Spacing.standard)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
        )
    }

    private var outputSelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("OUTPUT")
                .studioText(.micro)
                .tracking(0.8)
                .foregroundStyle(StudioTheme.mutedText)

            Menu {
                Button("Master") {
                    session.setTrackOutputBus(trackID: track.id, busID: nil)
                }
                ForEach(buses) { bus in
                    Button(bus.name) {
                        session.setTrackOutputBus(trackID: track.id, busID: bus.id)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(StudioTheme.mutedText)
                    Text(summary.destinationLabel)
                        .studioText(.labelBold)
                        .foregroundStyle(StudioTheme.text)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(StudioTheme.mutedText)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(minWidth: 120, alignment: .leading)
                .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                        .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
                )
            }
            .buttonStyle(.plain)
            .help("Output routing")
            .accessibilityLabel("\(track.name) output")
            .accessibilityValue(summary.destinationLabel)
        }
    }

    private enum SendSlot {
        case a
        case b

        var title: String { self == .a ? "A" : "B" }
        var accent: Color { self == .a ? StudioTheme.cyan : StudioTheme.violet }
        var keyPath: WritableKeyPath<TrackMixSettings, Double> {
            self == .a ? \.sendA : \.sendB
        }
    }

    /// Send knobs move in place and drive the same `setTrackMix` path the
    /// mixer uses (the re-home reuses existing send semantics verbatim).
    private func sendKnob(_ slot: SendSlot, value: Double) -> some View {
        StudioRotaryKnob(
            title: "SEND \(slot.title)",
            value: MixerSendDisplayModel.clamped(value),
            range: TrackMixSettings.sendRange,
            accent: slot.accent,
            size: 40,
            format: { MixerSendDisplayModel.percentLabel(for: $0) },
            onChange: { commitSend(slot, value: $0) },
            onLiveChange: { commitSend(slot, value: $0) }
        )
        .help("\(track.name) Send \(slot.title)")
        .accessibilityIdentifier("routing-send-\(slot.title.lowercased())")
    }

    private func commitSend(_ slot: SendSlot, value: Double) {
        var mix = track.mix
        mix[keyPath: slot.keyPath] = MixerSendDisplayModel.clamped(value)
        session.setTrackMix(trackID: track.id, mix: mix)
    }
}
