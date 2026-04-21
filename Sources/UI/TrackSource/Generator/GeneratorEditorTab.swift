import Foundation

enum GeneratorEditorTab: String, CaseIterable, Identifiable {
    case steps
    case pitches
    case notes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .steps:
            return "Trigger"
        case .pitches:
            return "Pitch"
        case .notes:
            return "Notes"
        }
    }
}
