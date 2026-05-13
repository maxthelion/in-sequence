import SwiftUI

struct MixerWorkspaceView: View {
    @Binding var document: SeqAIDocument
    let onSelectTrack: (UUID) -> Void
    @Environment(EngineController.self) private var engineController
    @State private var isMasterOverlayPresented = false

    var body: some View {
        GeometryReader { proxy in
            let presentation = MasterOutputColumnLayout.presentation(for: proxy.size.width)

            VStack(alignment: .leading, spacing: 18) {
                StudioPanel(title: "Mixer", eyebrow: "Track strips active now", accent: StudioTheme.cyan) {
                    masterAwareMixer(presentation: presentation)
                }

                StudioPanel(title: "Voice Routes", eyebrow: "Future drum and sliced-loop mixer coverage", accent: StudioTheme.violet) {
                    VStack(spacing: 12) {
                        StudioPlaceholderTile(title: "Tagged Voices", detail: "Drum and slice tracks")
                        StudioPlaceholderTile(title: "Per-Voice Treatment", detail: "Mute, bus, FX, and gain")
                    }
                }
            }
            .padding(20)
            .onChange(of: presentation.usesCompactOverlay) {
                if !presentation.usesCompactOverlay {
                    isMasterOverlayPresented = false
                }
            }
        }
        .frame(minHeight: 640)
    }

    private func masterAwareMixer(presentation: MasterOutputColumnPresentation) -> some View {
        ZStack(alignment: .trailing) {
            HStack(alignment: .top, spacing: 14) {
                MixerView(document: $document, onEditTrack: onSelectTrack)
                    .frame(maxWidth: .infinity, minHeight: 420, alignment: .topLeading)

                switch presentation {
                case .fullColumn:
                    MasterOutputColumnView()
                case let .compactStrip(width):
                    MasterOutputCompactStrip(
                        width: width,
                        isExpanded: isMasterOverlayPresented,
                        meterState: engineController.masterMeterPublisher.displayState
                    ) {
                        isMasterOverlayPresented.toggle()
                    }
                }
            }

            if presentation.usesCompactOverlay, isMasterOverlayPresented {
                MasterOutputColumnView()
                    .shadow(color: .black.opacity(0.35), radius: 18, x: -8, y: 8)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(2)
            }
        }
    }
}

private struct MasterOutputCompactStrip: View {
    let width: CGFloat
    let isExpanded: Bool
    let meterState: MasterMeterDisplayState
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            VStack(spacing: 8) {
                Image(systemName: isExpanded ? "chevron.right" : "slider.vertical.3")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(StudioTheme.text)

                Text("MSTR")
                    .studioText(.micro)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)
                    .rotationEffect(.degrees(-90))
                    .frame(width: 34, height: 24)

                CompactMasterMeter(state: meterState)
                    .frame(width: 12, height: 110)

                if meterState.isClipLatched {
                    Text("CLIP")
                        .studioText(.micro)
                        .tracking(0.8)
                        .foregroundStyle(Color.red)
                        .rotationEffect(.degrees(-90))
                        .frame(width: 34, height: 24)
                }
            }
            .frame(width: width)
            .frame(minHeight: 300)
            .padding(.vertical, 10)
            .background(StudioTheme.panelFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                    .stroke(StudioTheme.amber.opacity(0.7), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Master Out")
        .accessibilityIdentifier("mixer-master-out-compact-strip")
    }
}

private struct CompactMasterMeter: View {
    let state: MasterMeterDisplayState

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let peak = max(
                MasterMeterLevelScale.normalized(state.leftPeakDBFS),
                MasterMeterLevelScale.normalized(state.rightPeakDBFS)
            )
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                        .fill(state.isClipLatched ? Color.red : StudioTheme.success)
                        .frame(height: max(4, height * peak))
                }
        }
    }
}
