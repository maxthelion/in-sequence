import SwiftUI
import XCTest
@testable import SequencerAI

/// Tests for Step 3 of the "AU as a drum-part sound source" feature: the kit
/// Sound mini-tab branching (sampler vs AU panel), the "Load AU…" affordance
/// wiring (setEditedDestination(.auInstrument…) for the member), and the AU
/// preset browser bound to the member (loadPreset + writeStateBlob(.track(id))).
@MainActor
final class DrumKitSoundTabAUTests: XCTestCase {

    // MARK: - Helpers

    private final class DocumentBox {
        var document: SeqAIDocument
        init(document: SeqAIDocument) { self.document = document }
    }

    private func makeSession(project: Project) -> (SequencerDocumentSession, DocumentBox) {
        let box = DocumentBox(document: SeqAIDocument(project: project))
        let session = SequencerDocumentSession(
            document: Binding(
                get: { box.document },
                set: { box.document = $0 }
            ),
            engineController: EngineController(client: nil, endpoint: nil)
        )
        return (session, box)
    }

    private func makeAUComponentID() -> AudioComponentID {
        AudioComponentID(type: "aumu", subtype: "test", manufacturer: "test", version: 1)
    }

    private func makeTempLibrary() throws -> AudioSampleLibrary {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for name in ["kick", "snare", "hatClosed", "clap"] {
            let directory = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data().write(to: directory.appendingPathComponent("\(name)-default.wav"))
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return AudioSampleLibrary(libraryRoot: root)
    }

    private func makeDrumMember() throws -> (Project, UUID) {
        let library = try makeTempLibrary()
        var project = Project.empty
        guard let groupID = project.addDrumGroup(plan: .blankDefault, library: library),
              let memberID = project.trackGroups.first(where: { $0.id == groupID })?.memberIDs.first
        else {
            throw XCTSkip("expected a populated drum group with at least one member")
        }
        return (project, memberID)
    }

    // MARK: - Sound-tab routing (sampler vs AU panel)

    /// The Sound tab must show the AU panel only for a member whose OWN
    /// destination is an AU instrument; sampler/none/inheritGroup stay on the
    /// sampler+placeholder path.
    func test_soundTabRouting_choosesAUPanelOnlyForAUInstrument() {
        XCTAssertTrue(
            DrumKitSoundTabRouting.usesAUPanel(
                forOwnDestination: .auInstrument(componentID: makeAUComponentID(), stateBlob: nil)
            ),
            "An AU-instrument destination must route to the AU panel"
        )
        // stateBlob present must still route to the AU panel (transient state is stripped).
        XCTAssertTrue(
            DrumKitSoundTabRouting.usesAUPanel(
                forOwnDestination: .auInstrument(componentID: makeAUComponentID(), stateBlob: Data([1, 2, 3]))
            ),
            "An AU-instrument with a state blob must still route to the AU panel"
        )
        XCTAssertFalse(
            DrumKitSoundTabRouting.usesAUPanel(forOwnDestination: .sample(sampleID: UUID(), settings: .default)),
            "A sample destination must route to the sampler panel"
        )
        XCTAssertFalse(
            DrumKitSoundTabRouting.usesAUPanel(forOwnDestination: .none),
            "A cleared destination must route to the sampler/placeholder panel"
        )
        XCTAssertFalse(
            DrumKitSoundTabRouting.usesAUPanel(forOwnDestination: .inheritGroup),
            "An inheritGroup member must NOT route to the per-member AU panel (open product decision)"
        )
    }

    /// Regression guard: an `.inheritGroup` member of an AU kit RESOLVES to
    /// `.auInstrument` (via the group's sharedDestination), but the Sound tab must
    /// route on the member's OWN destination so the per-member AU panel is NOT
    /// shown for an inherited group AU. Routing on `resolvedDestination` here would
    /// wrongly show the AU panel (its preset/remove are keyed to a host the member
    /// doesn't own).
    func test_inheritGroupMember_ofAUKit_doesNotRouteToAUPanel() throws {
        var (project, memberID) = try makeDrumMember()

        // Make the group itself an AU, and the member inherit it (construct the
        // state directly — there is no group-target session mutation).
        let groupID = try XCTUnwrap(project.tracks.first(where: { $0.id == memberID })?.groupID)
        let groupIndex = try XCTUnwrap(project.trackGroups.firstIndex(where: { $0.id == groupID }))
        project.trackGroups[groupIndex].sharedDestination = .auInstrument(componentID: makeAUComponentID(), stateBlob: nil)
        let memberIndex = try XCTUnwrap(project.tracks.firstIndex(where: { $0.id == memberID }))
        project.tracks[memberIndex].destination = .inheritGroup

        let (session, _) = makeSession(project: project)

        let live = session.store.exportToProject()
        let member = try XCTUnwrap(live.tracks.first(where: { $0.id == memberID }))
        XCTAssertEqual(member.destination.kind, .inheritGroup,
            "Precondition: the member's OWN destination is .inheritGroup")
        XCTAssertEqual(session.store.resolvedDestination(for: memberID).kind, .auInstrument,
            "Precondition: it RESOLVES to the group's .auInstrument")

        // The routing decision (on the OWN destination) must NOT use the AU panel.
        XCTAssertFalse(
            DrumKitSoundTabRouting.usesAUPanel(forOwnDestination: member.destination),
            "An inherit member of an AU kit must keep the sampler/placeholder path, not the per-member AU panel"
        )

        SequencerDocumentSessionRegistry.unregister(session)
    }

    // MARK: - "Load AU…" affordance wiring

    /// Selecting an AU in the "Load AU…" sheet must swap the member's sampler
    /// sound for an AU instrument via session.setEditedDestination(.auInstrument…).
    func test_loadAU_setsAUInstrumentDestinationForMember() throws {
        let (project, memberID) = try makeDrumMember()

        XCTAssertEqual(
            project.tracks.first(where: { $0.id == memberID })?.destination.kind, .sample,
            "Precondition: blankDefault member starts on the sampler"
        )

        let (session, _) = makeSession(project: project)

        // The sheet's onCommit closure ultimately calls setEditedDestination on
        // the member. Exercise the same session mutation directly.
        let componentID = makeAUComponentID()
        session.setEditedDestination(.auInstrument(componentID: componentID, stateBlob: nil), for: memberID)

        let liveProject = session.store.exportToProject()
        let member = try XCTUnwrap(liveProject.tracks.first(where: { $0.id == memberID }))
        XCTAssertEqual(member.destination.kind, .auInstrument,
            "Loading an AU must set the member's destination to .auInstrument")

        // After the swap the Sound tab must render the AU panel (member's own AU).
        XCTAssertTrue(DrumKitSoundTabRouting.usesAUPanel(forOwnDestination: member.destination))

        SequencerDocumentSessionRegistry.unregister(session)
    }

    /// The per-track filter must remain STORED on the part when it swaps to an AU
    /// (dormant-but-stored), so toggling back to the sampler restores it.
    func test_swapToAU_keepsFilterStoredForRestore() throws {
        let (project, memberID) = try makeDrumMember()
        let (session, _) = makeSession(project: project)

        // Author a non-default filter on the sampler part.
        var customFilter = SamplerFilterSettings()
        customFilter.cutoffHz = 1234
        customFilter.resonance = 0.42
        session.setFilterSettings(customFilter, for: memberID)

        // Swap to an AU.
        session.setEditedDestination(.auInstrument(componentID: makeAUComponentID(), stateBlob: nil), for: memberID)

        let liveProject = session.store.exportToProject()
        let member = try XCTUnwrap(liveProject.tracks.first(where: { $0.id == memberID }))
        XCTAssertEqual(member.destination.kind, .auInstrument)
        XCTAssertEqual(member.filter.cutoffHz, 1234,
            "Filter cutoff must stay stored on the part while it hosts an AU (restores on toggle back)")
        XCTAssertEqual(member.filter.resonance, 0.42, accuracy: 0.0001,
            "Filter resonance must stay stored on the part while it hosts an AU")

        SequencerDocumentSessionRegistry.unregister(session)
    }

    // MARK: - AU preset browser bound to the member

    /// The member preset-browser view model must load the chosen preset through
    /// the per-member load op and commit the captured state blob to the member's
    /// own write target — modeled here with stub closures the kit factory wires.
    func test_memberPresetBrowser_loadInvokesLoadAndCommit() {
        var loadedDescriptorID: String?
        var committedBlob: Data?
        let expectedBlob = Data([9, 9, 9])

        let viewModel = PresetBrowserSheetViewModel(
            read: {
                PresetReadout(factory: [.factory(number: 0, name: "Init")], user: [], currentID: nil)
            },
            load: { descriptor in
                loadedDescriptorID = descriptor.id
                return expectedBlob
            },
            commit: { blob in
                committedBlob = blob
            }
        )

        viewModel.reload()
        let descriptor = AUPresetDescriptor.factory(number: 0, name: "Init")
        viewModel.load(descriptor)

        XCTAssertEqual(loadedDescriptorID, descriptor.id,
            "Selecting a preset must invoke the per-member load op (engineController.loadPreset(for: memberID))")
        XCTAssertEqual(committedBlob, expectedBlob,
            "The captured state blob must be committed (session.writeStateBlob(target: .track(memberID)))")
        XCTAssertEqual(viewModel.loadedID, descriptor.id,
            "The loaded preset must become the selected row")
    }
}
