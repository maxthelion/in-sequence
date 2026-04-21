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
                    .font(.system(size: 28, weight: .bold, design: .rounded))
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
