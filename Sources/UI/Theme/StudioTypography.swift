import SwiftUI

enum StudioTypography: String, CaseIterable, Sendable {
    case eyebrow
    case eyebrowBold
    case label
    case labelBold
    case body
    case bodyBold
    case bodyEmphasis
    case micro
    case microEmphasis
    case subtitle
    case subtitleMuted
    case title
    case metricValue
    case placeholderTitle
    case display
    case chromeLabel

    var size: CGFloat {
        switch self {
        case .micro, .microEmphasis:
            return 10
        case .eyebrow, .eyebrowBold:
            return 11
        case .label, .labelBold, .chromeLabel:
            return 12
        case .body, .bodyBold, .bodyEmphasis:
            return 13
        case .subtitle, .subtitleMuted, .metricValue:
            return 14
        case .placeholderTitle:
            return 15
        case .title:
            return 18
        case .display:
            return 28
        }
    }

    var weight: Font.Weight {
        switch self {
        case .eyebrow, .bodyEmphasis, .metricValue, .placeholderTitle, .microEmphasis:
            return .semibold
        case .label, .body, .subtitleMuted:
            return .medium
        case .eyebrowBold, .labelBold, .bodyBold, .micro, .subtitle, .title, .display, .chromeLabel:
            return .bold
        }
    }

    var design: Font.Design {
        switch self {
        case .chromeLabel:
            return .default
        default:
            return .rounded
        }
    }

    var font: Font {
        .system(size: size, weight: weight, design: design)
    }
}

extension View {
    func studioText(_ style: StudioTypography) -> some View {
        font(style.font)
    }
}
