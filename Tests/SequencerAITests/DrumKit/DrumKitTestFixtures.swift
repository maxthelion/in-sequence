import Foundation
@testable import SequencerAI

/// Shared fixtures for factory drum kits/templates in tests.
enum DrumKitFixtures {
    static func factoryKit(named name: String) -> DrumKit {
        guard let kit = DrumAssetLibrary.factoryKits.first(where: { $0.name == name }) else {
            preconditionFailure("missing factory kit named \(name)")
        }
        return kit
    }

    static func factoryTemplate(named name: String) -> PatternTemplate {
        guard let template = DrumAssetLibrary.factoryTemplates.first(where: { $0.name == name }) else {
            preconditionFailure("missing factory template named \(name)")
        }
        return template
    }

    /// Template lookup over factory content only — keeps tests off the
    /// app-support DrumAssetLibrary.shared instance.
    static let factoryTemplateLookup: (UUID) -> PatternTemplate? = { id in
        DrumAssetLibrary.factoryTemplates.first(where: { $0.id == id })
    }

    /// A creation plan for the named factory kit with its same-named factory
    /// template attached (the old "templated preset" behavior).
    static func templatedPlan(named name: String) -> DrumGroupPlan {
        .from(kit: factoryKit(named: name), templateID: factoryTemplate(named: name).id)
    }
}
