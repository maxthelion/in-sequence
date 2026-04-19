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
