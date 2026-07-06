import SwiftUI

/// Per-track FX insert chain UI (track-view IA, AC4 + AC5).
///
/// Each insert is one row with a drag handle (reorder — no up/down arrows), a
/// name + subtitle, and a bypass toggle + remove (✕) on the SAME line. Inserts
/// are added via a dashed full-width Add FX tile (not an "Insert" dropdown).
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

    // MARK: - Empty state

    private var emptyState: some View {
        StudioAddCard(
            label: "",
            accent: accent,
            minHeight: 132,
            backgroundColor: StudioTheme.background.opacity(0.72),
            help: "Add FX"
        ) {
            onAddFX()
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

            StudioAddCard(
                label: "Add FX",
                accent: accent,
                minHeight: 64,
                backgroundColor: StudioTheme.background.opacity(0.72),
                help: "Add FX"
            ) {
                onAddFX()
            }
        }
    }

    private var listHeight: CGFloat {
        let rowHeight: CGFloat = 56
        let visibleRows = min(inserts.count, 5)
        return CGFloat(visibleRows) * rowHeight
    }

    private func insertRow(_ insert: TrackFXInsert) -> some View {
        InsertChainRow(
            title: insert.name,
            subtitle: insert.subtitle,
            iconName: Self.iconName(for: insert.kind),
            accent: accent,
            isBypassed: insert.bypassed,
            iconSize: 11,
            iconWell: 22,
            iconCornerRadius: StudioMetrics.CornerRadius.badge,
            showsSelection: false,
            onToggleBypass: { onSetBypassed(insert.id, $0) },
            onRemove: { onRemove(insert.id) }
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
