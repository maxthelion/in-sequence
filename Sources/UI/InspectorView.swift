import SwiftUI

struct InspectorView: View {
    var body: some View {
        VStack(alignment: .leading) {
            Text("Inspector").font(.headline).padding(.bottom, 4)
            Text("Nothing selected").foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .frame(minWidth: 220)
    }
}

#Preview {
    InspectorView()
}
