import SwiftUI

/// Shared, scrollable, searchable AU-effect list for the mixer FX pickers
/// (master out, mixer bus, send return, scenes). Replaces the old hard
/// `prefix(16)` cap so effects past "P" no longer vanish: every installed
/// effect is reachable through the scroll view, and the search field filters
/// by display name for quick access.
struct AUEffectPickerList<Row: View>: View {
    let effects: [AudioEffectChoice]
    var maxHeight: CGFloat = 260
    @ViewBuilder var row: (AudioEffectChoice) -> Row

    @State private var query = ""

    private var filtered: [AudioEffectChoice] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return effects }
        return effects.filter {
            $0.displayName.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if effects.count > 8 {
                StudioSearchBar(placeholder: "Search effects", text: $query)
            }

            if effects.isEmpty {
                StudioEmptyListRow(message: "No AU effects found")
                    .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous))
            } else if filtered.isEmpty {
                StudioEmptyListRow(message: "No effects match “\(query)”")
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(filtered) { effect in
                            row(effect)
                        }
                    }
                }
                .frame(maxHeight: maxHeight)
                .scrollContentBackground(.hidden)
            }
        }
    }
}
