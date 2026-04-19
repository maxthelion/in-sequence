struct NoteShape: Codable, Equatable, Sendable {
    var velocity: Int
    var gateLength: Int
    var accent: Bool

    static let `default` = NoteShape(velocity: 100, gateLength: 4, accent: false)
}
