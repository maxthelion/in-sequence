import SwiftUI

/// State accent tokens for the section-pill status badges of the melodic/poly
/// track detail (kept from the underline-tab era: the badges carry real
/// display state — Clip/Gen/Empty, Mod/Byp — with a state colour).
enum TrackSourceSlotWellTabAccentToken: Equatable {
    case trackAccent
    case success
    case violet
    case amber
    case border

    func color(trackAccent: Color) -> Color {
        switch self {
        case .trackAccent:
            return trackAccent
        case .success:
            return StudioTheme.success
        case .violet:
            return StudioTheme.violet
        case .amber:
            return StudioTheme.amber
        case .border:
            return StudioTheme.border
        }
    }
}

/// Display-state → badge-accent mapping for the STEPS/CLIP and MACROS pills.
///
/// The unified tab grammar (Variant D, owner-locked 2026-07-02) reserves the
/// selected-thumb fill for the one surface accent, so this mapping now drives
/// the status badges only.
struct TrackSourceSlotWellTabAccentPresentation: Equatable {
    let badge: TrackSourceSlotWellTabAccentToken

    static func source(for state: TrackSourceSourceDisplayState) -> TrackSourceSlotWellTabAccentPresentation {
        switch state {
        case .occupiedClip:
            return TrackSourceSlotWellTabAccentPresentation(badge: .success)
        case .occupiedGenerator:
            return TrackSourceSlotWellTabAccentPresentation(badge: .trackAccent)
        case .empty:
            return TrackSourceSlotWellTabAccentPresentation(badge: .border)
        }
    }

    static func modifier(for state: TrackSourceModifierDisplayState) -> TrackSourceSlotWellTabAccentPresentation {
        switch state {
        case .occupied:
            return TrackSourceSlotWellTabAccentPresentation(badge: .violet)
        case .bypassed:
            return TrackSourceSlotWellTabAccentPresentation(badge: .amber)
        case .empty:
            return TrackSourceSlotWellTabAccentPresentation(badge: .border)
        case .unavailable:
            return TrackSourceSlotWellTabAccentPresentation(badge: .border)
        }
    }
}

enum TrackSourceHistoryDisplayState: Equatable {
    case liveCapture
    case unavailable(reason: String)

    var badgeTitle: String {
        switch self {
        case .liveCapture:
            return "Live"
        case .unavailable:
            return "N/A"
        }
    }

    var isAvailable: Bool {
        switch self {
        case .liveCapture:
            return true
        case .unavailable:
            return false
        }
    }

    static func resolve(
        trackType: TrackType,
        sourceState: TrackSourceSourceDisplayState
    ) -> TrackSourceHistoryDisplayState {
        guard trackType != .slice else {
            return .unavailable(reason: "History is unavailable for slice tracks.")
        }

        switch sourceState {
        case .occupiedGenerator, .occupiedClip:
            return .liveCapture
        case .empty:
            return .unavailable(reason: "Assign a source to build live history.")
        }
    }
}

/// Status badges shared by the SOUND and MIXER pills — real state only
/// (instrument name, destination), never a subtitle explainer.
struct TrackSourceRoutingDisplayState: Equatable {
    let soundBadgeTitle: String
    /// Destination label shown on the MIXER pill badge, e.g. "Master"/"Bus A".
    let mixerBadgeTitle: String
}

/// The melodic/poly track-detail section switcher: the D-pill grammar
/// (`StudioSectionPills`) floating above the `StudioTabWell`, with SOLID
/// status badges carrying the source/modifier/routing display state.
struct TrackSourceSectionPills: View {
    @Binding var selectedTab: TrackSourceEditorTab
    let sourceState: TrackSourceSourceDisplayState
    let modifierState: TrackSourceModifierDisplayState
    let routingState: TrackSourceRoutingDisplayState
    let accent: Color

    var body: some View {
        StudioSectionPills(
            pills: [
                StudioSectionPill(
                    section: TrackSourceEditorTab.stepsClip,
                    title: TrackSourceEditorTab.stepsClip.title,
                    badgeTitle: sourceState.badgeTitle,
                    badgeAccent: badgeColor(TrackSourceSlotWellTabAccentPresentation.source(for: sourceState)),
                    accessibilityIdentifier: "track-detail-tab-steps-clip"
                ),
                StudioSectionPill(
                    section: TrackSourceEditorTab.sound,
                    title: TrackSourceEditorTab.sound.title,
                    badgeTitle: routingState.soundBadgeTitle,
                    badgeAccent: StudioTheme.success,
                    accessibilityIdentifier: "track-detail-tab-sound"
                ),
                StudioSectionPill(
                    section: TrackSourceEditorTab.fx,
                    title: TrackSourceEditorTab.fx.title,
                    badgeTitle: "Insert",
                    badgeAccent: StudioTheme.violet,
                    accessibilityIdentifier: "track-detail-tab-fx"
                ),
                StudioSectionPill(
                    section: TrackSourceEditorTab.macros,
                    title: TrackSourceEditorTab.macros.title,
                    badgeTitle: modifierState.badgeTitle,
                    badgeAccent: badgeColor(TrackSourceSlotWellTabAccentPresentation.modifier(for: modifierState)),
                    accessibilityIdentifier: "track-detail-tab-macros"
                ),
                StudioSectionPill(
                    section: TrackSourceEditorTab.mixer,
                    title: TrackSourceEditorTab.mixer.title,
                    badgeTitle: routingState.mixerBadgeTitle,
                    badgeAccent: StudioTheme.success,
                    accessibilityIdentifier: "track-mixer-tab"
                ),
            ],
            selection: selectedTab,
            accent: accent,
            accessibilityIdentifier: "track-detail-tabs",
            onSelect: { selectedTab = $0 }
        )
    }

    private func badgeColor(_ presentation: TrackSourceSlotWellTabAccentPresentation) -> Color {
        presentation.badge.color(trackAccent: accent)
    }
}
