import SwiftUI

struct StudioTopBar: View {
    @Binding var section: WorkspaceSection
    @Binding var document: SeqAIDocument
    @Environment(SequencerDocumentSession.self) private var session

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

                if session.workspaceMode == .perform {
                    quantisePill
                }
                workspaceModeControl
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

    /// The ONE global SETUP/PERFORM switch (perform/setup split slice 1).
    /// Same pill grammar as the page pills; the active mode is a solid block
    /// — violet for setup, amber for perform (colour identifies the mode).
    /// The whole capsule is the hit target (ux-canon rule 2).
    private var workspaceModeControl: some View {
        HStack(spacing: 6) {
            ForEach(WorkspaceMode.allCases) { mode in
                Button {
                    session.workspaceMode = mode
                } label: {
                    Text(mode.title.uppercased())
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .tracking(0.9)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .foregroundStyle(session.workspaceMode == mode ? StudioTheme.background : StudioTheme.mutedText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .frame(minWidth: 78)
                        .background(modeFill(for: mode), in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(modeStroke(for: mode), lineWidth: StudioMetrics.borderWidth)
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("workspace-mode-\(mode.rawValue)")
                .accessibilityValue(session.workspaceMode == mode ? "Selected" : "Not selected")
                .help(mode == .setup
                    ? "Setup configures: instruments, routing, macro assignment"
                    : "Perform plays: pattern, mute, fill — what you hear next bar")
            }
        }
    }

    /// The quantise pill (perform/setup split slice 2, wireframes §2): one
    /// tap flips Q:BAR ↔ Q:OFF. Same pill grammar as the mode switch —
    /// Q:BAR is a solid amber block (toggles land on the bar), Q:OFF is a
    /// dashed ghost outline (toggles land immediately). Perform mode only.
    private var quantisePill: some View {
        Button {
            session.performQuantise = session.performQuantise.flipped
        } label: {
            Text(session.performQuantise.pillLabel)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .tracking(0.9)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .foregroundStyle(session.performQuantise == .bar ? StudioTheme.background : StudioTheme.mutedText)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(minWidth: 78)
                .background(
                    session.performQuantise == .bar ? StudioTheme.amber : Color.clear,
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .stroke(
                            session.performQuantise == .bar ? StudioTheme.amber : StudioTheme.border,
                            style: QuantisedTogglePresentation.strokeStyle(
                                isPending: session.performQuantise == .off,
                                lineWidth: StudioMetrics.borderWidth
                            )
                        )
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("perform-quantise-pill")
        .accessibilityValue(session.performQuantise == .bar ? "Bar" : "Off")
        .help(session.performQuantise == .bar
            ? "Perform toggles land at the next bar boundary; tap for immediate"
            : "Perform toggles land immediately; tap to quantise to the bar")
    }

    private func modeAccent(for mode: WorkspaceMode) -> Color {
        mode == .perform ? StudioTheme.amber : StudioTheme.violet
    }

    private func modeFill(for mode: WorkspaceMode) -> Color {
        session.workspaceMode == mode ? modeAccent(for: mode) : Color.clear
    }

    private func modeStroke(for mode: WorkspaceMode) -> Color {
        session.workspaceMode == mode ? modeAccent(for: mode) : StudioTheme.border
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
