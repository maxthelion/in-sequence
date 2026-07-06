import SwiftUI

func layerAccent(_ layerID: String) -> Color {
    StudioTheme.phraseAccent
}

func layerSubtitle(_ layer: PhraseLayerDefinition) -> String {
    switch layer.target {
    case .patternIndex:
        return "pattern slot"
    case .mute:
        return "track mute"
    case let .macroRow(name):
        return name
    case .blockParam:
        return "block param"
    case .voiceRouteOverride:
        return "voice route"
    case .macroParam:
        return "macro param"
    }
}
