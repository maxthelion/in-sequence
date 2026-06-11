import SwiftUI

/// Section chrome for a workspace surface.
///
/// `title` names a *section*, never the page: the selected top-nav pill
/// already says where the user is, so page-level panels pass
/// `showsHeader: false` (or an empty title with an `accessory`) instead of
/// restating it. `accessory` is a trailing control that belongs to the panel
/// (e.g. a mode toggle) and renders in the header row.
struct StudioPanel<Content: View, Accessory: View>: View {
    let title: String
    var eyebrow: String? = nil
    var accent: Color = StudioTheme.cyan
    var showsHeader = true
    let content: Content
    let accessory: Accessory

    init(
        title: String,
        eyebrow: String? = nil,
        accent: Color = StudioTheme.cyan,
        showsHeader: Bool = true,
        @ViewBuilder content: () -> Content,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.eyebrow = eyebrow
        self.accent = accent
        self.showsHeader = showsHeader
        self.content = content()
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsHeader {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 10) {
                        if !title.isEmpty {
                            Text(title.uppercased())
                                .studioText(.bodyEmphasis)
                                .tracking(1.1)
                                .foregroundStyle(StudioTheme.text)

                            Rectangle()
                                .fill(accent)
                                .frame(width: 36, height: 2)
                        }

                        Spacer()

                        accessory
                    }

                    if let eyebrow {
                        Text(eyebrow)
                            .studioText(.label)
                            .foregroundStyle(StudioTheme.mutedText)
                    }
                }
            }

            content
        }
        .padding(StudioMetrics.Spacing.loose)
        // Flat variant: the panel separates from the stage by solid colour
        // value alone — no stroke, no drop shadow.
        .background(StudioTheme.panelFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.section, style: .continuous))
    }
}

extension StudioPanel where Accessory == EmptyView {
    init(
        title: String,
        eyebrow: String? = nil,
        accent: Color = StudioTheme.cyan,
        showsHeader: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            eyebrow: eyebrow,
            accent: accent,
            showsHeader: showsHeader,
            content: content,
            accessory: { EmptyView() }
        )
    }
}
