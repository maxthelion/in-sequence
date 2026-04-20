import Foundation

enum DrumKitNoteMap {
    static let baselineNote = 36

    static let table: [VoiceTag: UInt8] = [
        "kick": 36,
        "snare": 38,
        "sidestick": 37,
        "hat-closed": 42,
        "hat-open": 46,
        "hat-pedal": 44,
        "clap": 39,
        "tom-low": 41,
        "tom-mid": 45,
        "tom-hi": 48,
        "ride": 51,
        "crash": 49,
        "cowbell": 56,
        "tambourine": 54,
        "shaker": 70,
    ]

    static func note(for tag: VoiceTag) -> UInt8 {
        table[tag] ?? 60
    }
}
