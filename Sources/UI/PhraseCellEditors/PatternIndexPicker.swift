import SwiftUI

struct PatternIndexPicker: View {
    @Binding var selectedIndex: Int
    var accent: Color = StudioTheme.phraseAccent

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(0..<TrackPatternBank.slotCount, id: \.self) { index in
                    Button {
                        selectedIndex = index
                    } label: {
                        Text("P\(index + 1)")
                            .studioText(.eyebrowBold)
                            .foregroundStyle(index == selectedIndex ? StudioTheme.background : StudioTheme.text)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(index == selectedIndex ? accent : StudioTheme.subtleFill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
