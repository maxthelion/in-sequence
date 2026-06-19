import SwiftUI

/// Per-track FX insert chain UI (track-view IA, AC4 + AC5).
///
/// Each insert is one row with a drag handle (reorder — no up/down arrows), a
/// name + subtitle, and a bypass toggle + remove (✕) on the SAME line. Inserts
/// are added via a "+ FX" button (not an "Insert" dropdown). The empty state is
/// a single compact line + the "+ FX" button — no "Enabled" label and no large
/// "Empty"/"Empty Scene" filler text (AC5).
struct TrackFXChainView: View {
    let inserts: [TrackFXInsert]
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
        .padding(StudioMetrics.Spacing.standard)
    }

    // MARK: - Empty state (AC5: compact only)

    private var emptyState: some View {
        HStack(spacing: 12) {
            Text("No inserts yet.")
                .studioText(.body)
                .foregroundStyle(StudioTheme.mutedText)
            Spacer(minLength: 0)
            addFXButton
        }
    }

    // MARK: - Populated chain

    private var chainList: some View {
        VStack(alignment: .leading, spacing: 10) {
            // A List with `.onMove` gives the drag-to-reorder handle without
            // any up/down arrow buttons (AC4). Height is bounded so it sits
            // inside the FX tab body rather than expanding unbounded.
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

    private func insertRow(_ insert: TrackFXInsert) -> some View {
        let icon = Self.iconName(for: insert.kind)
        let subtitle = insert.subtitle
        return HStack(spacing: 10) {
            // Drag handle (AC4: reorder by handle, never arrows).
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

            // Bypass toggle (AC5: no "Enabled" text label).
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
        .opacity(insert.bypassed ? 0.55 : 1)
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
        .accessibilityLabel("Add FX insert")
    }

    private func bypassBinding(_ insert: TrackFXInsert) -> Binding<Bool> {
        // The switch reads "on" as active (not bypassed) so the green tint
        // means "processing".
        Binding(
            get: { !insert.bypassed },
            set: { isActive in onSetBypassed(insert.id, !isActive) }
        )
    }

    static func iconName(for kind: MasterBusInsertKind) -> String {
        switch kind {
        case .nativeFilter:
            return "line.3.horizontal.decrease.circle"
        case .nativeBitcrusher:
            return "waveform.path.ecg"
        case .auEffect:
            return "slider.horizontal.3"
        }
    }
}
