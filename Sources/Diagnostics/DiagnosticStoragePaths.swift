import Foundation

struct DiagnosticStoragePaths: Equatable {
    let root: URL

    var diagnosticsRoot: URL {
        root.appendingPathComponent("diagnostics", isDirectory: true)
    }

    var eventsDirectory: URL {
        diagnosticsRoot.appendingPathComponent("events", isDirectory: true)
    }

    var currentEventsFile: URL {
        eventsDirectory.appendingPathComponent("current.ndjson")
    }

    var eventsArchiveDirectory: URL {
        eventsDirectory.appendingPathComponent("archive", isDirectory: true)
    }

    var issuesDirectory: URL {
        diagnosticsRoot.appendingPathComponent("issues", isDirectory: true)
    }

    var issueLedgerFile: URL {
        issuesDirectory.appendingPathComponent("ledger.json")
    }

    var issueEvidenceDirectory: URL {
        issuesDirectory.appendingPathComponent("evidence", isDirectory: true)
    }

    var reviewDirectory: URL {
        diagnosticsRoot.appendingPathComponent("review", isDirectory: true)
    }

    var reviewCandidatesDirectory: URL {
        reviewDirectory.appendingPathComponent("candidates", isDirectory: true)
    }

    var requiredDirectories: [URL] {
        [
            eventsDirectory,
            eventsArchiveDirectory,
            issuesDirectory,
            issueEvidenceDirectory,
            reviewCandidatesDirectory,
        ]
    }
}
