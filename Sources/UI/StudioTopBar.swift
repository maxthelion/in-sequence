import SwiftUI

struct StudioTopBar: View {
    @Binding var section: WorkspaceSection
    @Binding var document: SeqAIDocument

    private var visibleSections: [WorkspaceSection] {
        WorkspaceSection.allCases.filter { $0 != .track }
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 18) {
                Text("SequencerAI")
                    .studioText(.display)
                    .foregroundStyle(StudioTheme.text)

                Spacer(minLength: 20)

                TransportBar()
            }

            HStack(spacing: 10) {
                ForEach(visibleSections, id: \.self) { sectionValue in
                    Button {
                        section = sectionValue
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: sectionValue.systemImage)
                                .font(.system(size: 12, weight: .semibold))
                            Text(sectionValue.title.uppercased())
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .tracking(0.9)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        .foregroundStyle(section == sectionValue ? StudioTheme.text : StudioTheme.mutedText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(minWidth: 84)
                        .background(buttonFill(for: sectionValue), in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(buttonStroke(for: sectionValue), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
        }
        .padding(20)
        .background(StudioTheme.chrome.opacity(0.92), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chrome, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chrome, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: 1)
        )
    }

    private func buttonFill(for sectionValue: WorkspaceSection) -> Color {
        section == sectionValue ? StudioTheme.cyan.opacity(StudioOpacity.hoverFill) : Color.white.opacity(StudioOpacity.subtleFill)
    }

    private func buttonStroke(for sectionValue: WorkspaceSection) -> Color {
        section == sectionValue ? StudioTheme.cyan.opacity(StudioOpacity.mediumStroke) : StudioTheme.border
    }
}
