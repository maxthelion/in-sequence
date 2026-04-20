import SwiftUI

struct SliceIndexEditor: View {
    let sliceIndexes: [Int]
    let onChange: ([Int]) -> Void

    var body: some View {
        TextField(
            "Comma-separated slice indexes",
            text: Binding(
                get: { sliceIndexes.map(String.init).joined(separator: ", ") },
                set: { newValue in
                    let parsed = newValue
                        .split(separator: ",")
                        .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                    if !parsed.isEmpty {
                        onChange(parsed)
                    }
                }
            )
        )
        .textFieldStyle(.roundedBorder)
    }
}
