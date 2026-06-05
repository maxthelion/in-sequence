import XCTest
@testable import SequencerAI

final class DAWNoteNameTests: XCTestCase {
    func test_canonical_display_uses_sharps_and_daw_octaves() {
        XCTAssertEqual(DAWNoteName.string(forMIDINote: 36), "C2")
        XCTAssertEqual(DAWNoteName.string(forMIDINote: 39), "D#2")
        XCTAssertEqual(DAWNoteName.string(forMIDINote: 60), "C4")
        XCTAssertEqual(DAWNoteName.string(forNoteOffset: 10), "A#2")
    }

    func test_flats_normalize_to_canonical_sharp_display() {
        XCTAssertEqual(DAWNoteName.midiNote(from: "Db2"), 37)
        XCTAssertEqual(DAWNoteName.string(forMIDINote: DAWNoteName.midiNote(from: "Bb3") ?? -1), "A#3")
    }

    func test_lowercase_input_is_accepted() {
        XCTAssertEqual(DAWNoteName.midiNote(from: "c#2"), 37)
        XCTAssertEqual(DAWNoteName.noteOffset(from: "f#2"), 6)
    }

    func test_signed_octaves_cover_midi_range() {
        XCTAssertEqual(DAWNoteName.midiNote(from: "C-1"), 0)
        XCTAssertEqual(DAWNoteName.midiNote(from: "G9"), 127)
    }

    func test_range_bounds_reject_outside_midi_notes() {
        XCTAssertNil(DAWNoteName.midiNote(from: "B-2"))
        XCTAssertNil(DAWNoteName.midiNote(from: "G#9"))
        XCTAssertNil(DAWNoteName.string(forMIDINote: -1))
        XCTAssertNil(DAWNoteName.string(forMIDINote: 128))
    }

    func test_empty_and_partial_values_are_rejected() {
        XCTAssertNil(DAWNoteName.midiNote(from: ""))
        XCTAssertNil(DAWNoteName.midiNote(from: "  "))
        XCTAssertNil(DAWNoteName.midiNote(from: "C"))
        XCTAssertNil(DAWNoteName.midiNote(from: "C#"))
        XCTAssertNil(DAWNoteName.midiNote(from: "C 2"))
    }

    func test_raw_numeric_midi_note_input_is_rejected() {
        XCTAssertNil(DAWNoteName.midiNote(from: "60"))
        XCTAssertNil(DAWNoteName.midiNote(from: "-1"))
    }
}
