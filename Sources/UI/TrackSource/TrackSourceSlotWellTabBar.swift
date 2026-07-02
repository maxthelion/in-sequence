import SwiftUI

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
/// status badges carrying the source/modifier/routing display state as TEXT
/// ("Clip"/"Mod"/"Byp"/"Empty"). One chrome accent per surface (locked
/// Variant D): every badge renders in the track identity colour — state is
/// the badge title, never a second accent.
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
                    accessibilityIdentifier: "track-detail-tab-steps-clip"
                ),
                StudioSectionPill(
                    section: TrackSourceEditorTab.sound,
                    title: TrackSourceEditorTab.sound.title,
                    badgeTitle: routingState.soundBadgeTitle,
                    accessibilityIdentifier: "track-detail-tab-sound"
                ),
                StudioSectionPill(
                    section: TrackSourceEditorTab.fx,
                    title: TrackSourceEditorTab.fx.title,
                    badgeTitle: "Insert",
                    accessibilityIdentifier: "track-detail-tab-fx"
                ),
                StudioSectionPill(
                    section: TrackSourceEditorTab.macros,
                    title: TrackSourceEditorTab.macros.title,
                    badgeTitle: modifierState.badgeTitle,
                    accessibilityIdentifier: "track-detail-tab-macros"
                ),
                StudioSectionPill(
                    section: TrackSourceEditorTab.mixer,
                    title: TrackSourceEditorTab.mixer.title,
                    badgeTitle: routingState.mixerBadgeTitle,
                    accessibilityIdentifier: "track-mixer-tab"
                ),
            ],
            selection: selectedTab,
            accent: accent,
            accessibilityIdentifier: "track-detail-tabs",
            onSelect: { selectedTab = $0 }
        )
    }
}
