import SwiftUI

struct GeneratorAttachmentControl: View {
    let attachedGenerator: GeneratorPoolEntry?
    let accent: Color
    let onAdd: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let attached = attachedGenerator {
                VStack(alignment: .leading, spacing: 2) {
                    Text(attached.name)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(StudioTheme.text)
                    Text(attached.kind.label)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(StudioTheme.mutedText)
                }

                Spacer(minLength: 0)

                Button(action: onRemove) {
                    Text("Remove")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(StudioTheme.text)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 12)
                        .background(Color.white.opacity(0.06), in: Capsule())
                        .overlay(Capsule().stroke(StudioTheme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            } else {
                Button(action: onAdd) {
                    Text("Add Generator")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(StudioTheme.text)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 14)
                        .background(accent.opacity(0.18), in: Capsule())
                        .overlay(Capsule().stroke(accent.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }
        }
    }
}
