import SwiftUI

struct WrapRow: View {
    let items: [String]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .studioText(.labelBold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(StudioOpacity.subtleFill), in: Capsule())
                    .foregroundStyle(StudioTheme.text)
            }
        }
    }
}
