import Foundation
import os

/// Debug-build activity trace for post-mortem debugging. Events land in the
/// unified log and survive hangs and crashes, so the path to a problem can be
/// reconstructed afterwards with:
///
///   log show --last 10m --predicate 'subsystem == "ai.sequencer.SequencerAI.activity"'
///
/// or watched live with `log stream` and the same predicate. Traces compile
/// away in release builds.
enum DevActivity {
    static let subsystem = "ai.sequencer.SequencerAI.activity"

    static let engine = Logger(subsystem: subsystem, category: "engine")
    static let clock = Logger(subsystem: subsystem, category: "clock")
    static let audioGraph = Logger(subsystem: subsystem, category: "audio-graph")
    static let harness = Logger(subsystem: subsystem, category: "harness")
    static let session = Logger(subsystem: subsystem, category: "session")
    static let library = Logger(subsystem: subsystem, category: "library")

    /// One-line activity trace. The autoclosure keeps message construction
    /// out of release builds entirely.
    static func trace(_ logger: Logger, _ message: @autoclosure () -> String) {
        #if DEBUG
        let resolved = message()
        logger.info("\(resolved, privacy: .public)")
        #endif
    }
}
