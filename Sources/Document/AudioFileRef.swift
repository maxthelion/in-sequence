import Foundation

enum AudioFileRef: Codable, Equatable, Hashable, Sendable {
    case appSupportLibrary(relativePath: String)
    case projectPackage(filename: String)

    enum ResolveError: Error, Equatable {
        case missing
        case unsupportedScope
        case noLibraryRoot
    }

    /// Resolve to an on-disk URL.
    /// - Parameters:
    ///   - libraryRoot: root directory of the application-support sample library.
    ///   - packageRoot: reserved for the future project-scoped pool; pass nil in MVP.
    /// - Throws: `ResolveError.missing` if the file is absent on disk,
    ///           `ResolveError.unsupportedScope` for `.projectPackage` (deferred),
    ///           `ResolveError.noLibraryRoot` if libraryRoot is empty.
    func resolve(libraryRoot: URL, packageRoot: URL? = nil) throws -> URL {
        switch self {
        case .appSupportLibrary(let relativePath):
            guard !libraryRoot.path.isEmpty else { throw ResolveError.noLibraryRoot }
            let url = libraryRoot.appendingPathComponent(relativePath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw ResolveError.missing
            }
            return url
        case .projectPackage:
            throw ResolveError.unsupportedScope
        }
    }
}
