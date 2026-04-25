import Foundation

/// Drives the preset-browser sheet's two lists, its filter, and its load commit path.
///
/// The view model takes three closures so the SwiftUI view can plumb it into
/// `EngineController` + the document binding while tests can stub each side.
@MainActor
final class PresetBrowserSheetViewModel: ObservableObject {
    typealias ReadOp = () -> PresetReadout?
    typealias LoadOp = (AUPresetDescriptor) throws -> Data?
    typealias CommitOp = (Data?) -> Void

    @Published private(set) var factory: [AUPresetDescriptor] = []
    @Published private(set) var user: [AUPresetDescriptor] = []
    @Published var filter: String = ""
    @Published private(set) var loadedID: String?
    @Published private(set) var isReady: Bool = false
    @Published private(set) var lastLoadError: PresetLoadingError?

    private let read: ReadOp
    private let loader: LoadOp
    private let commit: CommitOp
    private var reloadGeneration: UInt64 = 0

    init(
        read: @escaping ReadOp,
        load: @escaping LoadOp,
        commit: @escaping CommitOp
    ) {
        self.read = read
        self.loader = load
        self.commit = commit
    }

    var filteredFactory: [AUPresetDescriptor] { filterApplied(to: factory) }
    var filteredUser: [AUPresetDescriptor] { filterApplied(to: user) }

    /// Refreshes the factory + user lists and the star's `loadedID`. If the AU is not
    /// yet live, leaves `isReady == false` so the sheet can show its loading placeholder.
    func reload() {
        applyReadout(read())
    }

    /// Refreshes preset lists without blocking the main actor while the live AU host
    /// resolves its current readout.
    func reloadAsync() {
        let generation = reloadGeneration &+ 1
        reloadGeneration = generation
        let read = self.read

        DispatchQueue.global(qos: .userInitiated).async {
            let readout = read()

            Task { @MainActor in
                guard generation == self.reloadGeneration else {
                    return
                }
                self.applyReadout(readout)
            }
        }
    }

    /// Loads `descriptor` into the live AU, writes the resulting state blob into the
    /// document, and moves the star to the newly-loaded preset. On
    /// `PresetLoadingError.presetNotFound`, records the error without clearing the star.
    /// On any other error, records `.loadFailed` with the underlying description and logs.
    func load(_ descriptor: AUPresetDescriptor) {
        do {
            let blob = try loader(descriptor)
            commit(blob)
            loadedID = descriptor.id
            lastLoadError = nil
        } catch let error as PresetLoadingError {
            lastLoadError = error
        } catch {
            lastLoadError = .loadFailed(underlying: String(describing: error))
            NSLog("[PresetBrowserSheet] load failed: \(error)")
        }
    }

    private func filterApplied(to list: [AUPresetDescriptor]) -> [AUPresetDescriptor] {
        guard !filter.isEmpty else {
            return list
        }
        return list.filter { $0.name.localizedCaseInsensitiveContains(filter) }
    }

    private func applyReadout(_ readout: PresetReadout?) {
        guard let readout else {
            factory = []
            user = []
            loadedID = nil
            isReady = false
            return
        }
        factory = readout.factory
        user = readout.user
        loadedID = readout.currentID
        isReady = true
    }
}
