import SwiftUI

struct AUPresetRowView: View {
    let descriptor: AUPresetDescriptor
    let isLoaded: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // The loaded preset is marked with a checkmark (the conventional
                // "currently selected" affordance). A star previously stood in for
                // this, but a star reads as "favourite", not "current", which made
                // the picker confusing. Unselected rows reserve the same width so
                // the names stay aligned.
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(StudioTheme.transportAccent)
                    .frame(width: 16)
                    .opacity(isLoaded ? 1 : 0)

                Text(descriptor.name)
                    .studioText(.body)
                    .foregroundStyle(isLoaded ? StudioTheme.text : StudioTheme.text.opacity(0.85))

                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}
