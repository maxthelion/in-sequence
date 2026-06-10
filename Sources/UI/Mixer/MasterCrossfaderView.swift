import SwiftUI

struct MasterCrossfaderView: View {
    let sceneAName: String
    let sceneBName: String
    let value: Double
    let hasLiveOverride: Bool
    var showsPersistenceActions = false
    let onChange: (Double) -> Void
    var onReset: (() -> Void)?
    var onSave: ((Double) -> Void)?

    var body: some View {
        content
            .padding(StudioMetrics.Spacing.compact)
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("master-crossfader")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            sceneNameRow
            sliderRow

            if showsPersistenceActions {
                actionRow
            }
        }
    }

    private var sceneNameRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            sceneBadge(slot: "A", frameAlignment: .leading)
            Spacer(minLength: 8)
            Text("\(Int((clampedValue * 100).rounded()))%")
                .studioText(.eyebrowBold)
                .monospacedDigit()
                .foregroundStyle(StudioTheme.text)
                .frame(width: 46, alignment: .center)
            Spacer(minLength: 8)
            sceneBadge(slot: "B", frameAlignment: .trailing)
        }
    }

    private var sliderRow: some View {
        Slider(
            value: Binding(
                get: { clampedValue },
                set: { onChange($0) }
            ),
            in: 0...1
        )
        .tint(StudioTheme.amber)
        .accessibilityLabel("Scene A B blend")
        .accessibilityValue("\(sceneAName) to \(sceneBName)")
        .accessibilityIdentifier("master-crossfader-slider")
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button {
                onReset?()
            } label: {
                Label("Reset", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.bordered)
            .disabled(!hasLiveOverride || onReset == nil)

            Button {
                onSave?(clampedValue)
            } label: {
                Label("Save Blend", systemImage: "tray.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .tint(StudioTheme.cyan)
            .disabled(!hasLiveOverride || onSave == nil)
        }
    }

    private var clampedValue: Double {
        min(max(value, 0), 1)
    }

    private func sceneBadge(
        slot: String,
        frameAlignment: Alignment
    ) -> some View {
        Text(slot)
            .studioText(.eyebrowBold)
            .foregroundStyle(StudioTheme.amber)
        .frame(maxWidth: .infinity, alignment: frameAlignment)
    }
}
