import SwiftUI

struct StudioTopBar: View {
    @Binding var section: WorkspaceSection
    @Binding var document: SeqAIDocument

    private let buildIdentity = BuildIdentity.current

    /// The badge is only worth showing when at least one of the fields it
    /// displays carries real data; local builds without the GIT_* build
    /// settings resolve every field to "unknown".
    private var buildIdentityIsMeaningful: Bool {
        [
            buildIdentity.gitBranch,
            buildIdentity.gitCommit,
            buildIdentity.gitDirty,
            buildIdentity.attributionVersion
        ].contains { $0 != "unknown" }
    }

    private var visibleSections: [WorkspaceSection] {
        WorkspaceSection.allCases.filter { $0 != .track }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                if buildIdentityIsMeaningful {
                    buildIdentityBadge
                }

                Spacer(minLength: 12)

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
                        .foregroundStyle(section == sectionValue ? StudioTheme.background : StudioTheme.mutedText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .frame(minWidth: 78)
                        .background(buttonFill(for: sectionValue), in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(buttonStroke(for: sectionValue), lineWidth: StudioMetrics.borderWidth)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(StudioTheme.chrome)
        .overlay(
            StudioTheme.border
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private var buildIdentityBadge: some View {
        Text(buildIdentity.compactDisplay)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(StudioTheme.mutedText)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
            )
            .help(buildIdentity.logSummary)
            .accessibilityLabel("Build identity \(buildIdentity.logSummary)")
    }

    /// Bold-flat pass: the selected pill is a fully solid accent block with a
    /// dark glyph inside; inactive pills are outline-only on the ground.
    private func buttonFill(for sectionValue: WorkspaceSection) -> Color {
        section == sectionValue ? StudioTheme.cyan : Color.clear
    }

    private func buttonStroke(for sectionValue: WorkspaceSection) -> Color {
        section == sectionValue ? StudioTheme.cyan : StudioTheme.border
    }
}
