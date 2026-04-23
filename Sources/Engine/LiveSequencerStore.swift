import Foundation
import Observation

enum LiveMutationImpact: Sendable {
    case snapshotOnly
    case fullEngineApply
    case documentOnly
}

@MainActor
@Observable
final class LiveSequencerStore {
    private(set) var project: Project
    private(set) var revision: UInt64 = 0

    init(project: Project) {
        self.project = project
    }

    @discardableResult
    func mutate(
        impact _: LiveMutationImpact = .snapshotOnly,
        _ update: (inout Project) -> Void
    ) -> Bool {
        var next = project
        update(&next)

        guard next != project else {
            return false
        }

        project = next
        revision &+= 1
        return true
    }

    @discardableResult
    func replaceProject(_ nextProject: Project) -> Bool {
        guard nextProject != project else {
            return false
        }

        project = nextProject
        revision &+= 1
        return true
    }

    func projectedProject() -> Project {
        project
    }
}
