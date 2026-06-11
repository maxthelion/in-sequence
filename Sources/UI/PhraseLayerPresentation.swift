import SwiftUI

func layerAccent(_ layerID: String) -> Color {
    switch layerID {
    case "pattern", "brightness", "register":
        return StudioTheme.violet
    case "mute", "fill-flag":
        return StudioTheme.success
    case "tension", "transpose", "swing":
        return StudioTheme.amber
    case "volume", "intensity", "density", "variance", "fx-send":
        return StudioTheme.cyan
    default:
        // Macro param layers follow the convention "macro-<trackID>-<bindingID>".
        if layerID.hasPrefix("macro-") {
            return StudioTheme.cyan
        }
        return StudioTheme.cyan
    }
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
