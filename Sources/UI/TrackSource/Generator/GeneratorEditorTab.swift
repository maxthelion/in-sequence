import Foundation

enum GeneratorEditorTab: String, CaseIterable, Identifiable {
    case steps
    case pitches
    case notes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .steps:
            return "Steps"
        case .pitches:
            return "Pitches"
        case .notes:
            return "Notes"
        }
    }
}
