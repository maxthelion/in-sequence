import SwiftUI

struct StudioTopBar: View {
    @Binding var section: WorkspaceSection
    @Binding var document: SeqAIDocument
    @Environment(EngineController.self) private var engineController

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SequencerAI")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(StudioTheme.text)

                    Text(section.subtitle.capitalized)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(StudioTheme.mutedText)
                }

                Spacer(minLength: 20)

                TransportBar()
            }

            HStack(spacing: 10) {
                ForEach(WorkspaceSection.allCases, id: \.self) { sectionValue in
                    Button {
                        section = sectionValue
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: sectionValue.systemImage)
                                .font(.system(size: 12, weight: .semibold))
                            Text(sectionValue.title.uppercased())
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .tracking(0.9)
                        }
                        .foregroundStyle(section == sectionValue ? StudioTheme.text : StudioTheme.mutedText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(minWidth: 94)
                        .background(buttonFill(for: sectionValue), in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(buttonStroke(for: sectionValue), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                StudioMetricPill(title: "Mode", value: section.title, accent: StudioTheme.amber)
                StudioMetricPill(title: "Track", value: document.model.selectedTrack.name, accent: StudioTheme.violet)
                StudioMetricPill(
                    title: "Engine",
                    value: engineController.isRunning ? "Running" : "Ready",
                    accent: engineController.isRunning ? StudioTheme.success : StudioTheme.cyan
                )
            }
        }
        .padding(20)
        .background(StudioTheme.chrome.opacity(0.92), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: 1)
        )
    }

    private func buttonFill(for sectionValue: WorkspaceSection) -> Color {
        section == sectionValue ? StudioTheme.cyan.opacity(0.16) : Color.white.opacity(0.03)
    }

    private func buttonStroke(for sectionValue: WorkspaceSection) -> Color {
        section == sectionValue ? StudioTheme.cyan.opacity(0.45) : StudioTheme.border
    }
}

struct TrackBankBar: View {
    @Binding var document: SeqAIDocument
    @Binding var section: WorkspaceSection

    var body: some View {
        HStack(spacing: 10) {
            ForEach(document.model.tracks, id: \.id) { track in
                Button {
                    document.model.selectTrack(id: track.id)
                    section = .track
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(track.name.uppercased())
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .tracking(0.9)
                            .foregroundStyle(StudioTheme.text)

                        HStack(spacing: 8) {
                            Text(track.trackType.shortLabel.uppercased())
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(StudioTheme.mutedText)

                            Text(track.output == .midiOut ? "MIDI" : "AUDIO")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(StudioTheme.mutedText)

                            Text("\(track.activeStepCount) STEPS")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(StudioTheme.mutedText)
                        }
                    }
                    .frame(width: 170, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(trackFill(for: track), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(trackStroke(for: track), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            Button {
                document.model.appendTrack()
                section = .track
            } label: {
                Label("Add Track", systemImage: "plus")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(StudioTheme.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(StudioTheme.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(18)
        .background(StudioTheme.chrome.opacity(0.78), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: 1)
        )
    }

    private func trackFill(for track: StepSequenceTrack) -> Color {
        document.model.selectedTrackID == track.id ? StudioTheme.violet.opacity(0.16) : Color.white.opacity(0.03)
    }

    private func trackStroke(for track: StepSequenceTrack) -> Color {
        document.model.selectedTrackID == track.id ? StudioTheme.violet.opacity(0.48) : StudioTheme.border
    }
}
