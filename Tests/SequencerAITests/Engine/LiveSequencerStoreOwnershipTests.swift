import XCTest
@testable import SequencerAI

@MainActor
final class LiveSequencerStoreOwnershipTests: XCTestCase {
    func test_store_mutation_does_not_mutate_source_project_value() {
        let (project, _, clipID) = makeLiveStoreProject(clipPitch: 60)
        let originalProject = project
        let store = LiveSequencerStore(project: project)

        XCTAssertTrue(
            store.mutate { workingProject in
                workingProject.updateClipEntry(id: clipID) { entry in
                    entry.content = .noteGrid(
                        lengthSteps: 1,
                        steps: [ClipStep(main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 72, velocity: 100, lengthSteps: 4)]), fill: nil)]
                    )
                }
            }
        )

        XCTAssertEqual(originalProject.clipEntry(id: clipID)?.pitchPool, [60])
        XCTAssertEqual(store.project.clipEntry(id: clipID)?.pitchPool, [72])
        XCTAssertEqual(store.projectedProject(), store.project)
    }
}
