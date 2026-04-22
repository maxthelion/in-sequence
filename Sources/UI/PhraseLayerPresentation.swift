import SwiftUI

func layerAccent(_ layerID: String) -> Color {
    switch layerID {
    case "pattern", "brightness", "register":
        return StudioTheme.violet
    case "mute", "fill-flag":
        return StudioTheme.success
    case "tension", "transpose":
        return StudioTheme.amber
    default:
        // Macro param layers follow the convention "macro-<trackID>-<bindingID>".
        if layerID.hasPrefix("macro-") {
            return StudioTheme.cyan
        }
        assertionFailure("Unhandled phrase layer accent id: \(layerID)")
        return StudioTheme.cyan
    }
}

func layerFill(_ layer: PhraseLayerDefinition, isSelected: Bool) -> Color {
    let accent = layerAccent(layer.id)
    return isSelected ? accent.opacity(StudioOpacity.hoverFill) : accent.opacity(0.05)
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
