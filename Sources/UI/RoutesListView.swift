import SwiftUI

struct RoutesListView: View {
    @Binding var document: SeqAIDocument
    @Environment(EngineController.self) private var engineController

    @State private var editingRoute: Route?

    private var selectedTrack: StepSequenceTrack {
        document.model.selectedTrack
    }

    private var routes: [Route] {
        document.model.routesSourced(from: selectedTrack.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                StudioMetricPill(title: "Routes Out", value: "\(routes.count)", accent: StudioTheme.violet)
                Spacer()
                Button("Add Route") {
                    editingRoute = document.model.makeDefaultRoute(from: selectedTrack.id)
                }
                .buttonStyle(.borderedProminent)
                .tint(StudioTheme.cyan)
            }

            if routes.isEmpty {
                StudioPlaceholderTile(
                    title: "No Project Routes Yet",
                    detail: "This track currently only plays to its own default destination. Add a route to duplicate notes to another track, a MIDI endpoint, or a chord-context lane.",
                    accent: StudioTheme.violet
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(routes) { route in
                        RouteRowView(
                            route: route,
                            trackLookup: trackLookup
                        ) {
                            editingRoute = route
                        } onDelete: {
                            document.model.removeRoute(id: route.id)
                        }
                    }
                }
            }
        }
        .sheet(item: $editingRoute) { route in
            RouteEditorSheet(
                tracks: document.model.tracks,
                midiEndpoints: engineController.availableMIDIDestinationNames,
                initialRoute: route
            ) { savedRoute in
                document.model.upsertRoute(savedRoute)
            }
        }
    }

    private func trackLookup(_ trackID: UUID) -> StepSequenceTrack? {
        document.model.tracks.first(where: { $0.id == trackID })
    }
}

private struct RouteRowView: View {
    let route: Route
    let trackLookup: (UUID) -> StepSequenceTrack?
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(route.destination.title(trackLookup: trackLookup))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(StudioTheme.text)

                    Text(route.description(trackLookup: trackLookup))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(StudioTheme.mutedText)
                }

                Spacer(minLength: 12)

                if !route.enabled {
                    Text("Disabled")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(StudioTheme.amber.opacity(0.12), in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(StudioTheme.amber.opacity(0.28), lineWidth: 1)
                        )
                }
            }

            HStack(spacing: 8) {
                Button("Edit", action: onEdit)
                    .buttonStyle(.borderedProminent)
                    .tint(StudioTheme.cyan)

                Button("Delete", role: .destructive, action: onDelete)
                    .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: 1)
        )
    }
}
