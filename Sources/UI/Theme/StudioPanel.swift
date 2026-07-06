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
    var accent: Color = StudioTheme.transportAccent
    var showsHeader = true
    var contentPadding: CGFloat = StudioMetrics.Spacing.loose
    let content: Content
    let accessory: Accessory

    init(
        title: String,
        eyebrow: String? = nil,
        accent: Color = StudioTheme.transportAccent,
        showsHeader: Bool = true,
        contentPadding: CGFloat = StudioMetrics.Spacing.loose,
        @ViewBuilder content: () -> Content,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.eyebrow = eyebrow
        self.accent = accent
        self.showsHeader = showsHeader
        self.contentPadding = contentPadding
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
        .padding(contentPadding)
        // Bold-flat pass: a panel is pure grouping — no fill at all. Content
        // sits directly on the single near-black ground; the header rule and
        // spacing do the separating.
    }
}

extension StudioPanel where Accessory == EmptyView {
    init(
        title: String,
        eyebrow: String? = nil,
        accent: Color = StudioTheme.transportAccent,
        showsHeader: Bool = true,
        contentPadding: CGFloat = StudioMetrics.Spacing.loose,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            eyebrow: eyebrow,
            accent: accent,
            showsHeader: showsHeader,
            contentPadding: contentPadding,
            content: content,
            accessory: { EmptyView() }
        )
    }
}
