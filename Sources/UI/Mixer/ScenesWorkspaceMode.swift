import Foundation

/// Legacy scenes-page mode vocabulary. The page itself now obeys the global
/// `WorkspaceMode` (setup ≙ browseEdit, perform ≙ perform); this enum
/// survives as the page's presentation switch plus the capture-harness
/// command/status vocabulary (`scenesMode=browseEdit|perform`) mapped onto
/// the global mode by VisualScenarioCommandRunner.
enum ScenesWorkspaceMode: String, CaseIterable, Identifiable {
    case browseEdit
    case perform

    var id: String { rawValue }

    var title: String {
        switch self {
        case .browseEdit:
            return "Browse/Edit"
        case .perform:
            return "Perform"
        }
    }
}
