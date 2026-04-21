import SwiftUI

struct GeneratorTabBar: View {
    @Binding var selectedTab: GeneratorEditorTab

    var body: some View {
        HStack(spacing: 8) {
            ForEach(GeneratorEditorTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.title)
                        .studioText(.labelBold)
                        .foregroundStyle(selectedTab == tab ? StudioTheme.text : StudioTheme.mutedText)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 12)
                        .background(selectedTab == tab ? StudioTheme.cyan.opacity(StudioOpacity.faintStroke) : Color.white.opacity(StudioOpacity.subtleFill), in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(selectedTab == tab ? StudioTheme.cyan.opacity(0.52) : StudioTheme.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }
}
