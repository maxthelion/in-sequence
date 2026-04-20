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
        assertionFailure("Unhandled phrase layer accent id: \(layerID)")
        return StudioTheme.cyan
    }
}

func layerFill(_ layer: PhraseLayerDefinition, isSelected: Bool) -> Color {
    let accent = layerAccent(layer.id)
    return isSelected ? accent.opacity(0.16) : accent.opacity(0.05)
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
    }
}
