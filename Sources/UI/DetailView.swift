import SwiftUI

struct DetailView: View {
    var body: some View {
        VStack(spacing: 0) {
            TransportBar()
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.quaternary)

            Divider()

            VStack {
                Text("Main content area")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    DetailView()
}
