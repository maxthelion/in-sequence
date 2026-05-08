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
            .padding(12)
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("master-crossfader")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            sceneNameRow
            sliderRow

            if showsPersistenceActions {
                actionRow
            }
        }
    }

    private var sceneNameRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            sceneBadge(slot: "A", name: sceneAName, alignment: .leading, frameAlignment: .leading)
            Spacer(minLength: 6)
            Text("\(Int((clampedValue * 100).rounded()))%")
                .studioText(.eyebrowBold)
                .monospacedDigit()
                .foregroundStyle(StudioTheme.text)
                .frame(width: 48, alignment: .trailing)
            Spacer(minLength: 6)
            sceneBadge(slot: "B", name: sceneBName, alignment: .trailing, frameAlignment: .trailing)
        }
    }

    private var sliderRow: some View {
        HStack(spacing: 10) {
            Text("A")
                .studioText(.eyebrowBold)
                .foregroundStyle(StudioTheme.amber)

            Slider(
                value: Binding(
                    get: { clampedValue },
                    set: { onChange($0) }
                ),
                in: 0...1
            )
            .tint(StudioTheme.amber)
            .accessibilityIdentifier("master-crossfader-slider")

            Text("B")
                .studioText(.eyebrowBold)
                .foregroundStyle(StudioTheme.amber)
        }
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
        name: String,
        alignment: HorizontalAlignment,
        frameAlignment: Alignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(slot)
                .studioText(.micro)
                .tracking(0.8)
                .foregroundStyle(StudioTheme.amber)
            Text(name)
                .studioText(.labelBold)
                .foregroundStyle(StudioTheme.text)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: 68, alignment: frameAlignment)
    }
}
