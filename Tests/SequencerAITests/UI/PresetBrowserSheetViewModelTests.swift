import XCTest
@testable import SequencerAI

@MainActor
final class PresetBrowserSheetViewModelTests: XCTestCase {

    // MARK: – reload() / readiness

    func test_reload_nil_readout_leaves_view_model_not_ready_with_empty_lists() {
        let viewModel = PresetBrowserSheetViewModel(
            read: { nil },
            load: { _ in XCTFail("load not expected"); return nil },
            commit: { _ in XCTFail("commit not expected") }
        )

        viewModel.reload()

        XCTAssertFalse(viewModel.isReady)
        XCTAssertEqual(viewModel.factory, [])
        XCTAssertEqual(viewModel.user, [])
        XCTAssertNil(viewModel.loadedID)
    }

    func test_reload_populates_lists_and_current_id_from_readout() {
        let readout = PresetReadout(
            factory: [.factory(number: 0, name: "Init"), .factory(number: 3, name: "Analog Keys")],
            user: [.user(number: -1, name: "My Pad")],
            currentID: "factory:3"
        )
        let viewModel = PresetBrowserSheetViewModel(
            read: { readout },
            load: { _ in nil },
            commit: { _ in }
        )

        viewModel.reload()

        XCTAssertTrue(viewModel.isReady)
        XCTAssertEqual(viewModel.factory.count, 2)
        XCTAssertEqual(viewModel.user.count, 1)
        XCTAssertEqual(viewModel.loadedID, "factory:3")
    }

    func test_reload_clears_state_when_AU_becomes_unavailable_mid_session() {
        var callCount = 0
        let viewModel = PresetBrowserSheetViewModel(
            read: {
                callCount += 1
                if callCount == 1 {
                    return PresetReadout(
                        factory: [.factory(number: 0, name: "Init")],
                        user: [],
                        currentID: "factory:0"
                    )
                }
                return nil
            },
            load: { _ in nil },
            commit: { _ in }
        )

        viewModel.reload()
        XCTAssertTrue(viewModel.isReady)
        XCTAssertEqual(viewModel.factory.count, 1)

        viewModel.reload()
        XCTAssertFalse(viewModel.isReady)
        XCTAssertEqual(viewModel.factory, [])
        XCTAssertNil(viewModel.loadedID,
                     "loadedID must clear when the AU goes away — otherwise a stale star persists across AU reloads")
    }

    // MARK: – filter

    func test_filter_matches_case_insensitive_substring_on_name() {
        let readout = PresetReadout(
            factory: [
                .factory(number: 1, name: "Analog Keys"),
                .factory(number: 2, name: "Mega Analog"),
                .factory(number: 3, name: "Digital Bells")
            ],
            user: [],
            currentID: nil
        )
        let viewModel = PresetBrowserSheetViewModel(
            read: { readout },
            load: { _ in nil },
            commit: { _ in }
        )
        viewModel.reload()

        viewModel.filter = "analog"
        XCTAssertEqual(viewModel.filteredFactory.map(\.name), ["Analog Keys", "Mega Analog"])

        viewModel.filter = "DIGITAL"
        XCTAssertEqual(viewModel.filteredFactory.map(\.name), ["Digital Bells"])
    }

    func test_filter_empty_string_returns_full_lists() {
        let readout = PresetReadout(
            factory: [.factory(number: 1, name: "A"), .factory(number: 2, name: "B")],
            user: [.user(number: -1, name: "C")],
            currentID: nil
        )
        let viewModel = PresetBrowserSheetViewModel(
            read: { readout },
            load: { _ in nil },
            commit: { _ in }
        )
        viewModel.reload()

        viewModel.filter = ""
        XCTAssertEqual(viewModel.filteredFactory.count, 2)
        XCTAssertEqual(viewModel.filteredUser.count, 1)
    }

    func test_filter_applies_to_both_factory_and_user_sections() {
        let readout = PresetReadout(
            factory: [.factory(number: 1, name: "Analog Bass"), .factory(number: 2, name: "Pad")],
            user: [.user(number: -1, name: "Analog Setup"), .user(number: -2, name: "Session")],
            currentID: nil
        )
        let viewModel = PresetBrowserSheetViewModel(
            read: { readout },
            load: { _ in nil },
            commit: { _ in }
        )
        viewModel.reload()

        viewModel.filter = "analog"
        XCTAssertEqual(viewModel.filteredFactory.map(\.name), ["Analog Bass"])
        XCTAssertEqual(viewModel.filteredUser.map(\.name), ["Analog Setup"])
    }

    // MARK: – load()

    func test_load_success_updates_loadedID_and_commits_blob() {
        let descriptor = AUPresetDescriptor.factory(number: 3, name: "Analog Keys")
        let blob = Data("preset-blob".utf8)
        var committedBlob: Data?
        let viewModel = PresetBrowserSheetViewModel(
            read: { nil },
            load: { d in
                XCTAssertEqual(d, descriptor)
                return blob
            },
            commit: { committedBlob = $0 }
        )

        viewModel.load(descriptor)

        XCTAssertEqual(viewModel.loadedID, "factory:3")
        XCTAssertEqual(committedBlob, blob)
        XCTAssertNil(viewModel.lastLoadError)
    }

    func test_load_success_with_nil_blob_still_commits_and_stars() {
        let descriptor = AUPresetDescriptor.factory(number: 1, name: "X")
        var commitCount = 0
        let viewModel = PresetBrowserSheetViewModel(
            read: { nil },
            load: { _ in nil },
            commit: { _ in commitCount += 1 }
        )

        viewModel.load(descriptor)

        XCTAssertEqual(viewModel.loadedID, descriptor.id)
        XCTAssertEqual(commitCount, 1,
                       "commit must run even when the AU's fullState encode returns nil — the star should still move")
    }

    func test_load_presetNotFound_sets_error_without_changing_loadedID() {
        let viewModel = PresetBrowserSheetViewModel(
            read: {
                PresetReadout(
                    factory: [.factory(number: 0, name: "Init")],
                    user: [],
                    currentID: "factory:0"
                )
            },
            load: { _ in throw PresetLoadingError.presetNotFound },
            commit: { _ in XCTFail("commit must not run on error") }
        )
        viewModel.reload()
        XCTAssertEqual(viewModel.loadedID, "factory:0")

        viewModel.load(.factory(number: 99, name: "Gone"))

        XCTAssertEqual(viewModel.loadedID, "factory:0",
                       "Failed load must not move the star off the currently-loaded preset")
        XCTAssertEqual(viewModel.lastLoadError, .presetNotFound)
    }

    func test_successful_load_clears_previous_load_error() {
        var shouldFail = true
        let viewModel = PresetBrowserSheetViewModel(
            read: { nil },
            load: { _ in
                if shouldFail {
                    throw PresetLoadingError.presetNotFound
                }
                return Data()
            },
            commit: { _ in }
        )

        viewModel.load(.factory(number: 1, name: "Missing"))
        XCTAssertEqual(viewModel.lastLoadError, .presetNotFound)

        shouldFail = false
        viewModel.load(.factory(number: 2, name: "Good"))
        XCTAssertNil(viewModel.lastLoadError)
        XCTAssertEqual(viewModel.loadedID, "factory:2")
    }

    func test_load_throws_non_PresetLoadingError_reports_loadFailed_not_presetNotFound() {
        struct StubError: Error {}
        let viewModel = PresetBrowserSheetViewModel(
            read: { nil },
            load: { _ in throw StubError() },
            commit: { _ in XCTFail("commit must not run on error") }
        )

        viewModel.load(.factory(number: 1, name: "X"))

        guard case .loadFailed(let underlying) = viewModel.lastLoadError else {
            return XCTFail("Expected .loadFailed, got \(String(describing: viewModel.lastLoadError))")
        }
        XCTAssertFalse(underlying.isEmpty, "Underlying description must be non-empty")
    }

    // MARK: – reloadAsync()

    func test_reloadAsync_populates_lists_and_current_id_from_readout() async {
        let readout = PresetReadout(
            factory: [.factory(number: 0, name: "Init"), .factory(number: 3, name: "Analog Keys")],
            user: [.user(number: -1, name: "My Pad")],
            currentID: "factory:3"
        )
        let viewModel = PresetBrowserSheetViewModel(
            read: { readout },
            load: { _ in nil },
            commit: { _ in }
        )

        viewModel.reloadAsync()
        await waitUntil("view model becomes ready after async read") {
            viewModel.isReady
        }

        XCTAssertTrue(viewModel.isReady)
        XCTAssertEqual(viewModel.factory.count, 2)
        XCTAssertEqual(viewModel.user.count, 1)
        XCTAssertEqual(viewModel.loadedID, "factory:3")
    }

    func test_reloadAsync_nil_readout_leaves_view_model_not_ready() async {
        let viewModel = PresetBrowserSheetViewModel(
            read: { nil },
            load: { _ in nil },
            commit: { _ in }
        )

        viewModel.reloadAsync()
        await waitUntil("async read completes with empty lists") {
            !viewModel.isReady && viewModel.factory.isEmpty && viewModel.user.isEmpty
        }

        XCTAssertFalse(viewModel.isReady)
        XCTAssertEqual(viewModel.factory, [])
        XCTAssertEqual(viewModel.user, [])
        XCTAssertNil(viewModel.loadedID)
    }

    func test_writeTarget_resolution_is_live_not_captured() {
        // Simulate a commit closure that re-resolves its target on each call.
        // Two calls with different targets returned by the resolver must each
        // write to the correct target.
        var targetToReturn = "first"
        var writtenTargets: [String] = []

        let viewModel = PresetBrowserSheetViewModel(
            read: { nil },
            load: { _ in Data() },
            commit: { _ in
                writtenTargets.append(targetToReturn)
            }
        )

        targetToReturn = "first"
        viewModel.load(.factory(number: 1, name: "A"))
        targetToReturn = "second"
        viewModel.load(.factory(number: 2, name: "B"))

        XCTAssertEqual(writtenTargets, ["first", "second"],
                       "Each commit must observe the live target value, not a captured snapshot")
    }

    private func waitUntil(
        _ description: String,
        timeout: Duration = .seconds(1),
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTFail("Timed out waiting for condition: \(description)")
    }
}
