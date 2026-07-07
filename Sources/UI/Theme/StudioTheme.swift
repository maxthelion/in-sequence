import SwiftUI

enum StudioTheme {
    private static let backgroundRed = 0.051
    private static let backgroundGreen = 0.051
    private static let backgroundBlue = 0.063
    private static let borderRed = 0.384
    private static let borderGreen = 0.384
    private static let borderBlue = 0.424

    /// Bold-flat pass: ONE near-black ground (~#0d0d10). Window, top bar,
    /// stage, and panels all sit on this single value; grouping reads from
    /// spacing, dividers, and outlines — never from another grey rectangle.
    static let background = Color(red: backgroundRed, green: backgroundGreen, blue: backgroundBlue)
    static let chrome = background

    /// Panels are pure grouping: same ground as the stage. A card/control may
    /// take at most one opaque fill step above this (see `subtleFill`), or no
    /// fill at all — outline only.
    static let panel = background

    /// Solid darker well for inset tracks/lanes (step wells, fader tracks,
    /// segmented control troughs); reads as a cut below the single ground.
    static let inset = Color(red: 0.024, green: 0.024, blue: 0.032)

    /// Drawn-line outline (~#62626c): clearly visible mid-grey on the
    /// near-black ground, the default idiom for inactive controls.
    static let border = Color(red: borderRed, green: borderGreen, blue: borderBlue)

    static let text = Color(red: 0.91, green: 0.91, blue: 0.925)
    static let mutedText = Color(red: 0.604, green: 0.604, blue: 0.643)
    static let cyan = Color(red: 0.00, green: 0.80, blue: 1.00)
    static let amber = Color(red: 1.00, green: 0.53, blue: 0.22)
    static let violet = Color(red: 0.63, green: 0.53, blue: 1.00)
    static let success = Color(red: 0.30, green: 0.92, blue: 0.52)
    static let danger = Color(red: 1.00, green: 0.32, blue: 0.34)

    /// Limited-colour role tokens. UI code should prefer these roles over raw
    /// hue names so a surface has one intentional accent instead of a rainbow
    /// of category colours.
    static let transportAccent = cyan
    static let phraseAccent = cyan
    static let neutral = border
    static let warning = amber
    static let patternPalette: [Color] = [
        Color(red: 0.00, green: 0.80, blue: 1.00),
        Color(red: 1.00, green: 0.53, blue: 0.22),
        Color(red: 0.63, green: 0.53, blue: 1.00),
        Color(red: 0.30, green: 0.92, blue: 0.52),
        Color(red: 1.00, green: 0.32, blue: 0.34),
        Color(red: 0.95, green: 0.82, blue: 0.28),
        Color(red: 0.23, green: 0.66, blue: 1.00),
        Color(red: 0.91, green: 0.42, blue: 0.78),
        Color(red: 0.44, green: 0.86, blue: 0.74),
        Color(red: 0.74, green: 0.62, blue: 1.00),
        Color(red: 1.00, green: 0.67, blue: 0.45),
        Color(red: 0.58, green: 0.78, blue: 1.00),
        Color(red: 0.80, green: 0.94, blue: 0.36),
        Color(red: 1.00, green: 0.48, blue: 0.58),
        Color(red: 0.36, green: 0.72, blue: 0.54),
        Color(red: 0.78, green: 0.78, blue: 0.92),
    ]

    static func patternColor(_ index: Int) -> Color {
        let count = max(patternPalette.count, 1)
        let wrapped = ((index % count) + count) % count
        return patternPalette[wrapped]
    }

    /// Bold-flat pass: panels and the stage share the single ground.
    static let panelFill = panel
    static let stageFill = background

    /// Opaque equivalents of the old translucent white fills. These preserve
    /// the intended single grey step on the near-black ground without allowing
    /// nested controls to compound brighter through alpha compositing.
    static let disabledSubtleFill = solidWhiteOverlay(0.015)
    static let subtleFill = solidWhiteOverlay(StudioOpacity.subtleFill)
    static let borderSubtleFill = solidWhiteOverlay(StudioOpacity.borderSubtle)
    static let borderFaintFill = solidWhiteOverlay(StudioOpacity.borderFaint)
    static let mutedFill = solidWhiteOverlay(StudioOpacity.mutedFill)
    static let softFill = solidWhiteOverlay(StudioOpacity.softFill)
    static let selectedFill = solidWhiteOverlay(StudioOpacity.selectedFill)
    static let strongFill = solidWhiteOverlay(0.85)
    static let ghostFill = solidWhiteOverlay(StudioOpacity.ghostStroke)
    static let dividerLowFill = solidWhiteOverlay(StudioOpacity.borderSubtle)
    static let dividerFaintFill = solidWhiteOverlay(StudioOpacity.faintStroke)
    static let dividerSubtleFill = solidWhiteOverlay(StudioOpacity.subtleStroke)
    static let borderLowFill = solidBorderOverlay(0.25)
    static let borderSubtleOverlayFill = solidBorderOverlay(0.35)
    static let borderSoftFill = solidBorderOverlay(StudioOpacity.softStroke)
    static let borderStrongFill = solidBorderOverlay(0.8)

    static func solidWhiteOverlay(_ alpha: CGFloat) -> Color {
        let clamped = min(max(Double(alpha), 0), 1)
        return Color(
            red: backgroundRed + (1 - backgroundRed) * clamped,
            green: backgroundGreen + (1 - backgroundGreen) * clamped,
            blue: backgroundBlue + (1 - backgroundBlue) * clamped
        )
    }

    static func solidBorderOverlay(_ alpha: CGFloat) -> Color {
        let clamped = min(max(Double(alpha), 0), 1)
        return Color(
            red: backgroundRed * (1 - clamped) + borderRed * clamped,
            green: backgroundGreen * (1 - clamped) + borderGreen * clamped,
            blue: backgroundBlue * (1 - clamped) + borderBlue * clamped
        )
    }

    static func color(hex: String) -> Color? {
        var string = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        string = string.replacingOccurrences(of: "#", with: "")
        guard string.count == 6, let value = UInt64(string, radix: 16) else {
            return nil
        }

        return Color(
            red: Double((value & 0xFF0000) >> 16) / 255.0,
            green: Double((value & 0x00FF00) >> 8) / 255.0,
            blue: Double(value & 0x0000FF) / 255.0
        )
    }

    static func identityAccent(for id: UUID) -> Color {
        color(hex: TrackPalette.identityHex(for: id)) ?? transportAccent
    }

    static func groupAccent(for group: TrackGroup) -> Color {
        if TrackPalette.isValidHex(group.color), let stored = color(hex: group.color) {
            return stored
        }
        return identityAccent(for: group.id)
    }

    static func trackAccent(for track: StepSequenceTrack, groups: [TrackGroup] = []) -> Color {
        if let groupID = track.groupID,
           let group = groups.first(where: { $0.id == groupID }) {
            return groupAccent(for: group)
        }
        return identityAccent(for: track.id)
    }
}
