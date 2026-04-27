import Foundation

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
