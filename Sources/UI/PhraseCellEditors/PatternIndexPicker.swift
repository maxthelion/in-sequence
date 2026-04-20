import SwiftUI

struct PatternIndexPicker: View {
    @Binding var selectedIndex: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(0..<TrackPatternBank.slotCount, id: \.self) { index in
                    Button {
                        selectedIndex = index
                    } label: {
                        Text("P\(index + 1)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(index == selectedIndex ? StudioTheme.violet.opacity(0.2) : Color.white.opacity(0.04), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
