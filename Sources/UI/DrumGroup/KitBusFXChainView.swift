import SwiftUI


/// Kit-bus FX insert chain (AC23). The same grammar as the per-track FX chain
/// (drag handle reorder, bypass + ✕ on one line, "+ FX" button, compact empty
/// state — no "Enabled"/"Empty" filler), but it edits the kit bus's
/// `MixerBusInsert` chain so the inserts process the whole kit at once.
struct KitBusFXChainView: View {
    let inserts: [MixerBusInsert]
    let accent: Color
    let onAddFX: () -> Void
    let onRemove: (UUID) -> Void
    let onMove: (IndexSet, Int) -> Void
    let onSetBypassed: (UUID, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if inserts.isEmpty {
                emptyState
            } else {
                chainList
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        HStack(spacing: 12) {
            Text("No inserts yet.")
                .studioText(.body)
                .foregroundStyle(StudioTheme.mutedText)
            Spacer(minLength: 0)
            addFXButton
        }
    }

    private var chainList: some View {
        VStack(alignment: .leading, spacing: 10) {
            List {
                ForEach(inserts) { insert in
                    insertRow(insert)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .onMove(perform: onMove)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(height: listHeight)

            HStack {
                Spacer(minLength: 0)
                addFXButton
            }
        }
    }

    private var listHeight: CGFloat {
        let rowHeight: CGFloat = 56
        let visibleRows = min(inserts.count, 5)
        return CGFloat(visibleRows) * rowHeight
    }

    private func insertRow(_ insert: MixerBusInsert) -> some View {
        let icon = TrackFXChainView.iconName(for: insert.kind)
        let subtitle = insert.kind.summary
        let bypassed = !insert.isEnabled
        return HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(StudioTheme.mutedText)
                .frame(width: 18)
                .accessibilityLabel("Reorder \(insert.name)")

            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(StudioTheme.background)
                .frame(width: 22, height: 22)
                .background(accent, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(insert.name)
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.text)
                    .lineLimit(1)
                Text(subtitle)
                    .studioText(.micro)
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Toggle("Bypass \(insert.name)", isOn: bypassBinding(insert))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(StudioTheme.success)

            Button {
                onRemove(insert.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(StudioTheme.mutedText)
            }
            .buttonStyle(.plain)
            .help("Remove insert")
            .accessibilityLabel("Remove \(insert.name)")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
        )
        .opacity(bypassed ? 0.55 : 1)
    }

    private var addFXButton: some View {
        Button(action: onAddFX) {
            Label("FX", systemImage: "plus")
                .studioText(.labelBold)
                .foregroundStyle(StudioTheme.background)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add kit FX insert")
        .accessibilityIdentifier("kit-add-fx")
    }

    private func bypassBinding(_ insert: MixerBusInsert) -> Binding<Bool> {
        Binding(
            get: { insert.isEnabled },
            set: { isActive in onSetBypassed(insert.id, !isActive) }
        )
    }
}
