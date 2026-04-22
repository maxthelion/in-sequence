import SwiftUI

struct AUPresetRowView: View {
    let descriptor: AUPresetDescriptor
    let isLoaded: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: isLoaded ? "star.fill" : "star")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isLoaded ? StudioTheme.amber : StudioTheme.mutedText.opacity(0.4))
                    .frame(width: 16)

                Text(descriptor.name)
                    .studioText(.body)
                    .foregroundStyle(StudioTheme.text)

                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}
