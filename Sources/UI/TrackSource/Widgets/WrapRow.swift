import SwiftUI

struct WrapRow: View {
    let items: [String]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.04), in: Capsule())
                    .foregroundStyle(StudioTheme.text)
            }
        }
    }
}
