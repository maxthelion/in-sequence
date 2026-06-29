import Foundation

protocol DiagnosticEventWriting: AnyObject {
    func write(_ event: AppDiagnosticEvent) throws
}

final class DiagnosticEventWriter: DiagnosticEventWriting {
    private let paths: DiagnosticStoragePaths
    private let fileManager: FileManager
    private let encoder: JSONEncoder

    init(paths: DiagnosticStoragePaths, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
        self.encoder = DiagnosticEventWriter.makeEncoder()
    }

    func write(_ event: AppDiagnosticEvent) throws {
        try fileManager.createDirectory(
            at: paths.eventsDirectory,
            withIntermediateDirectories: true
        )

        var data = try encoder.encode(event)
        data.append(0x0A)

        if fileManager.fileExists(atPath: paths.currentEventsFile.path) {
            let handle = try FileHandle(forWritingTo: paths.currentEventsFile)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: paths.currentEventsFile, options: .atomic)
        }
    }

    static func encodedLine(for event: AppDiagnosticEvent) throws -> String {
        let data = try makeEncoder().encode(event)
        return String(decoding: data, as: UTF8.self)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
