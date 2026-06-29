import Foundation

/// Stable identity colours for tracks and drum groups (bug 20260629-100436).
///
/// Colour encodes IDENTITY (which track / which kit), not selection: a cell shows
/// its identity hue on its icon badge at all times, and selection is encoded
/// separately by the outline (a coloured 2px ring vs a thin grey border). A kit
/// and its member parts resolve to the SAME identity hue so they read as one
/// group at a glance.
///
/// Colours are derived deterministically from the entity's id rather than stored,
/// so they are stable across launches without a document-format migration. A
/// group that carries an explicit valid colour overrides the derived one.
enum TrackPalette {
    /// Valid 6-digit identity hexes, tuned to stay distinct on the dark stage.
    static let identityHexes: [String] = [
        "#4FA8D8", // cyan-blue
        "#E0833A", // amber
        "#8A6FE0", // violet
        "#54B98A", // green
        "#D8608F", // pink
        "#D6B23A", // gold
        "#46BDB0", // teal
        "#C06A45", // rust
    ]

    /// A palette hex by position, cycling and wrapping negative indices safely.
    static func identityHex(forIndex index: Int) -> String {
        let count = identityHexes.count
        return identityHexes[((index % count) + count) % count]
    }

    /// Run-stable palette slot for a UUID. Uses the first id byte rather than
    /// `hashValue`, which is seeded per process and would change a track's colour
    /// on every launch.
    static func identityHex(for id: UUID) -> String {
        identityHex(forIndex: Int(id.uuid.0))
    }

    /// Whether a stored colour string is a usable 6-digit hex (the legacy
    /// "#8AA" default is NOT — it is rejected, so the derived colour is used).
    static func isValidHex(_ hex: String) -> Bool {
        let stripped = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        return stripped.count == 6 && UInt64(stripped, radix: 16) != nil
    }
}
