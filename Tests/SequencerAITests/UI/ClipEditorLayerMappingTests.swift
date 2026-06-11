import XCTest
@testable import SequencerAI

/// Pins the Track Source clip editor's layer vocabulary to the shared
/// step-grid layer vocabulary so the Variant D rotary row, the grid cells,
/// and the coordinator all agree on which layer is being edited.
final class ClipEditorLayerMappingTests: XCTestCase {
    func test_editorLayersMapOntoSharedStepGridLayers() {
        XCTAssertEqual(ClipEditorLayer.mode(.trigger).stepGridLayer, .trigger)
        XCTAssertEqual(ClipEditorLayer.mode(.velocity).stepGridLayer, .velocity)
        XCTAssertEqual(ClipEditorLayer.mode(.probability).stepGridLayer, .chance)
        XCTAssertEqual(ClipEditorLayer.macro(index: 3).stepGridLayer, .macro(index: 3))
    }

    func test_stepGridLayersRoundTripBackToEditorLayers() {
        let editorLayers: [ClipEditorLayer] = [
            .mode(.trigger),
            .mode(.velocity),
            .mode(.probability),
            .macro(index: 0),
            .macro(index: 5),
        ]

        for layer in editorLayers {
            XCTAssertEqual(ClipEditorLayer(stepGridLayer: layer.stepGridLayer), layer)
        }
    }

    func test_slicerOnlyStepGridLayersHaveNoEditorLayer() {
        XCTAssertNil(ClipEditorLayer(stepGridLayer: .sliceIndex))
        XCTAssertNil(ClipEditorLayer(stepGridLayer: .sliceMode))
        XCTAssertNil(ClipEditorLayer(stepGridLayer: .chord))
    }

    /// Macro editor layers carry `TrackMacroBinding` array indexes, never the
    /// visual slot position — the rotary row and macro lane writes both key
    /// off the binding index.
    func test_macroEditorLayerCarriesBindingArrayIndexNotSlotPosition() {
        let firstBinding = TrackMacroBinding(
            descriptor: TrackMacroDescriptor.builtin(trackID: UUID(), kind: .sampleStart),
            slotIndex: 7
        )
        let secondBinding = TrackMacroBinding(
            descriptor: TrackMacroDescriptor.builtin(trackID: UUID(), kind: .sampleLength),
            slotIndex: 0
        )
        let tabs = ClipMacroLayerTab.tabs(
            macroSlots: [
                MacroSlot(slotIndex: 0, binding: secondBinding),
                MacroSlot(slotIndex: 7, binding: firstBinding),
            ],
            macroBindings: [firstBinding, secondBinding]
        )

        let layers = tabs.map { ClipEditorLayer.macro(index: $0.macroIndex) }

        XCTAssertEqual(layers.map(\.stepGridLayer), [.macro(index: 1), .macro(index: 0)])
    }
}
