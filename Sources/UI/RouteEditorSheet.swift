import SwiftUI

struct RouteEditorSheet: View {
    let tracks: [StepSequenceTrack]
    let midiEndpoints: [MIDIEndpointName]
    let initialRoute: Route
    let onSave: (Route) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var route: Route
    @State private var destinationKind: RouteDestinationKind

    init(
        tracks: [StepSequenceTrack],
        midiEndpoints: [MIDIEndpointName],
        initialRoute: Route,
        onSave: @escaping (Route) -> Void
    ) {
        self.tracks = tracks
        self.midiEndpoints = midiEndpoints
        self.initialRoute = initialRoute
        self.onSave = onSave
        _route = State(initialValue: initialRoute)
        _destinationKind = State(initialValue: RouteDestinationKind(initialRoute.destination))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Route Editor")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(StudioTheme.text)
                Spacer()
                Toggle("Enabled", isOn: $route.enabled)
                    .toggleStyle(.switch)
            }

            Form {
                Section("Source") {
                    Picker("Event Type", selection: sourceKindBinding) {
                        Text("Track Notes").tag(RouteSourceKind.track)
                        Text("Chord Generator").tag(RouteSourceKind.chordGenerator)
                    }
                    .pickerStyle(.segmented)

                    Picker("Track", selection: sourceTrackBinding) {
                        ForEach(tracks, id: \.id) { track in
                            Text(track.name).tag(track.id)
                        }
                    }
                }

                Section("Filter") {
                    Picker("Filter", selection: filterKindBinding) {
                        ForEach(RouteFilterKind.allCases, id: \.self) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch filterKindBinding.wrappedValue {
                    case .all:
                        EmptyView()
                    case .voiceTag:
                        TextField("Voice Tag", text: voiceTagBinding)
                    case .noteRange:
                        Stepper(value: noteRangeLowerBinding, in: 0...127) {
                            Text("Low Note: \(noteRangeLowerBinding.wrappedValue)")
                        }
                        Stepper(value: noteRangeUpperBinding, in: noteRangeLowerBinding.wrappedValue...127) {
                            Text("High Note: \(noteRangeUpperBinding.wrappedValue)")
                        }
                    }
                }

                Section("Destination") {
                    Picker("Type", selection: $destinationKind) {
                        ForEach(RouteDestinationKind.allCases, id: \.self) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: destinationKind) { _, newValue in
                        route.destination = newValue.makeDefault(using: tracks, midiEndpoints: midiEndpoints)
                    }

                    switch destinationKind {
                    case .voicing:
                        Picker("Target Track", selection: targetTrackBinding) {
                            ForEach(tracks, id: \.id) { track in
                                Text(track.name).tag(track.id)
                            }
                        }
                    case .trackInput:
                        Picker("Target Track", selection: targetTrackBinding) {
                            ForEach(tracks, id: \.id) { track in
                                Text(track.name).tag(track.id)
                            }
                        }
                        TextField("Input Tag (optional)", text: targetTagBinding)
                    case .midi:
                        Picker("Destination", selection: routeMIDIPortBinding) {
                            ForEach(midiEndpoints, id: \.self) { endpoint in
                                Text(endpoint.displayName).tag(endpoint)
                            }
                        }
                        Stepper(value: routeMIDIChannelBinding, in: 1...16) {
                            Text("Channel: \(routeMIDIChannelBinding.wrappedValue)")
                        }
                        Stepper(value: routeMIDIOffsetBinding, in: -24...24) {
                            Text("Transpose: \(routeMIDIOffsetBinding.wrappedValue)")
                        }
                    case .chordContext:
                        TextField("Lane (optional)", text: laneBinding)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Save") {
                    onSave(route)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(StudioTheme.cyan)
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 520)
        .background(StudioTheme.background)
    }

    private var sourceKindBinding: Binding<RouteSourceKind> {
        Binding(
            get: { RouteSourceKind(route.source) },
            set: { newKind in
                let trackID = sourceTrackBinding.wrappedValue
                route.source = newKind.makeSource(trackID: trackID)
            }
        )
    }

    private var sourceTrackBinding: Binding<UUID> {
        Binding(
            get: {
                switch route.source {
                case let .track(trackID), let .chordGenerator(trackID):
                    return trackID
                }
            },
            set: { newTrackID in
                route.source = sourceKindBinding.wrappedValue.makeSource(trackID: newTrackID)
            }
        )
    }

    private var filterKindBinding: Binding<RouteFilterKind> {
        Binding(
            get: { RouteFilterKind(route.filter) },
            set: { newKind in
                route.filter = newKind.makeFilter(from: route.filter)
            }
        )
    }

    private var voiceTagBinding: Binding<String> {
        Binding(
            get: {
                if case let .voiceTag(tag) = route.filter {
                    return tag
                }
                return ""
            },
            set: { route.filter = .voiceTag($0) }
        )
    }

    private var noteRangeLowerBinding: Binding<Int> {
        Binding(
            get: {
                if case let .noteRange(lo, _) = route.filter {
                    return Int(lo)
                }
                return 36
            },
            set: { newValue in
                let high = noteRangeUpperBinding.wrappedValue
                route.filter = .noteRange(lo: UInt8(newValue), hi: UInt8(max(newValue, high)))
            }
        )
    }

    private var noteRangeUpperBinding: Binding<Int> {
        Binding(
            get: {
                if case let .noteRange(_, hi) = route.filter {
                    return Int(hi)
                }
                return 84
            },
            set: { newValue in
                let low = noteRangeLowerBinding.wrappedValue
                route.filter = .noteRange(lo: UInt8(min(low, newValue)), hi: UInt8(newValue))
            }
        )
    }

    private var targetTrackBinding: Binding<UUID> {
        Binding(
            get: {
                switch route.destination {
                case let .voicing(trackID), let .trackInput(trackID, _):
                    return trackID
                case .midi, .chordContext:
                    return tracks.first?.id ?? UUID()
                }
            },
            set: { newTrackID in
                switch route.destination {
                case .voicing:
                    route.destination = .voicing(newTrackID)
                case let .trackInput(_, tag):
                    route.destination = .trackInput(newTrackID, tag: tag)
                case .midi, .chordContext:
                    break
                }
            }
        )
    }

    private var targetTagBinding: Binding<String> {
        Binding(
            get: {
                if case let .trackInput(_, tag) = route.destination {
                    return tag ?? ""
                }
                return ""
            },
            set: {
                guard case let .trackInput(trackID, _) = route.destination else {
                    return
                }
                route.destination = .trackInput(trackID, tag: $0.isEmpty ? nil : $0)
            }
        )
    }

    private var routeMIDIPortBinding: Binding<MIDIEndpointName> {
        Binding(
            get: {
                if case let .midi(port, _, _) = route.destination {
                    return port
                }
                return midiEndpoints.first ?? .sequencerAIOut
            },
            set: { newPort in
                let channel = routeMIDIChannelBinding.wrappedValue
                let offset = routeMIDIOffsetBinding.wrappedValue
                route.destination = .midi(port: newPort, channel: UInt8(channel - 1), noteOffset: offset)
            }
        )
    }

    private var routeMIDIChannelBinding: Binding<Int> {
        Binding(
            get: {
                if case let .midi(_, channel, _) = route.destination {
                    return Int(channel) + 1
                }
                return 1
            },
            set: { newValue in
                let port = routeMIDIPortBinding.wrappedValue
                let offset = routeMIDIOffsetBinding.wrappedValue
                route.destination = .midi(port: port, channel: UInt8(max(0, min(15, newValue - 1))), noteOffset: offset)
            }
        )
    }

    private var routeMIDIOffsetBinding: Binding<Int> {
        Binding(
            get: {
                if case let .midi(_, _, noteOffset) = route.destination {
                    return noteOffset
                }
                return 0
            },
            set: {
                let port = routeMIDIPortBinding.wrappedValue
                let channel = routeMIDIChannelBinding.wrappedValue
                route.destination = .midi(port: port, channel: UInt8(channel - 1), noteOffset: $0)
            }
        )
    }

    private var laneBinding: Binding<String> {
        Binding(
            get: {
                if case let .chordContext(tag) = route.destination {
                    return tag ?? ""
                }
                return ""
            },
            set: { route.destination = .chordContext(broadcastTag: $0.isEmpty ? nil : $0) }
        )
    }
}

private enum RouteSourceKind: CaseIterable {
    case track
    case chordGenerator

    init(_ source: RouteSource) {
        switch source {
        case .track:
            self = .track
        case .chordGenerator:
            self = .chordGenerator
        }
    }

    func makeSource(trackID: UUID) -> RouteSource {
        switch self {
        case .track:
            return .track(trackID)
        case .chordGenerator:
            return .chordGenerator(trackID)
        }
    }
}

private enum RouteFilterKind: CaseIterable {
    case all
    case voiceTag
    case noteRange

    init(_ filter: RouteFilter) {
        switch filter {
        case .all:
            self = .all
        case .voiceTag:
            self = .voiceTag
        case .noteRange:
            self = .noteRange
        }
    }

    var label: String {
        switch self {
        case .all:
            return "All"
        case .voiceTag:
            return "Voice"
        case .noteRange:
            return "Range"
        }
    }

    func makeFilter(from existing: RouteFilter) -> RouteFilter {
        switch self {
        case .all:
            return .all
        case .voiceTag:
            if case .voiceTag = existing {
                return existing
            }
            return .voiceTag(Voicing.defaultTag)
        case .noteRange:
            if case .noteRange = existing {
                return existing
            }
            return .noteRange(lo: 36, hi: 84)
        }
    }
}

private enum RouteDestinationKind: CaseIterable {
    case voicing
    case trackInput
    case midi
    case chordContext

    init(_ destination: RouteDestination) {
        switch destination {
        case .voicing:
            self = .voicing
        case .trackInput:
            self = .trackInput
        case .midi:
            self = .midi
        case .chordContext:
            self = .chordContext
        }
    }

    var label: String {
        switch self {
        case .voicing:
            return "Voicing"
        case .trackInput:
            return "Track Input"
        case .midi:
            return "MIDI"
        case .chordContext:
            return "Chord Lane"
        }
    }

    func makeDefault(using tracks: [StepSequenceTrack], midiEndpoints: [MIDIEndpointName]) -> RouteDestination {
        switch self {
        case .voicing:
            return .voicing(tracks.first?.id ?? UUID())
        case .trackInput:
            return .trackInput(tracks.first?.id ?? UUID(), tag: nil)
        case .midi:
            return .midi(port: midiEndpoints.first ?? .sequencerAIOut, channel: 0, noteOffset: 0)
        case .chordContext:
            return .chordContext(broadcastTag: nil)
        }
    }
}
