import Foundation

struct Project: Codable, Equatable {
    enum DestinationWriteTarget: Equatable, Sendable {
        case track(UUID)
        case group(TrackGroupID)
    }

    var version: Int
    var tracks: [StepSequenceTrack]
    var trackGroups: [TrackGroup]
    var generatorPool: [GeneratorPoolEntry]
    var clipPool: [ClipPoolEntry]
    var layers: [PhraseLayerDefinition]
    var routes: [Route]
    var buses: [MixerBus]
    var sendBusA: SendBusState
    var sendBusB: SendBusState
    var masterBus: MasterBusState
    var patternBanks: [TrackPatternBank]
    var sliceSetPool: [SliceSet]
    var selectedTrackID: UUID
    var phrases: [PhraseModel]
    var selectedPhraseID: UUID

    init(
        version: Int,
        tracks: [StepSequenceTrack],
        trackGroups: [TrackGroup] = [],
        generatorPool: [GeneratorPoolEntry] = GeneratorPoolEntry.defaultPool,
        clipPool: [ClipPoolEntry] = [],
        layers: [PhraseLayerDefinition] = [],
        routes: [Route] = [],
        buses: [MixerBus] = [],
        sendBusA: SendBusState = .sendA,
        sendBusB: SendBusState = .sendB,
        masterBus: MasterBusState = .default,
        patternBanks: [TrackPatternBank] = [],
        sliceSetPool: [SliceSet] = [],
        selectedTrackID: UUID,
        phrases: [PhraseModel],
        selectedPhraseID: UUID
    ) {
        let normalized = Self.normalize(
            tracks: tracks,
            generatorPool: generatorPool,
            clipPool: clipPool,
            layers: layers.isEmpty ? nil : layers,
            patternBanks: patternBanks.isEmpty ? nil : patternBanks,
            phrases: phrases.isEmpty ? nil : phrases,
            selectedTrackID: selectedTrackID,
            selectedPhraseID: selectedPhraseID
        )

        self.version = version
        let normalizedBuses = MixerBus.normalizedCollection(buses)
        self.tracks = Self.tracksByClearingMissingOutputBuses(tracks, buses: normalizedBuses)
        self.trackGroups = trackGroups
        self.generatorPool = generatorPool
        self.clipPool = clipPool
        self.layers = normalized.layers
        self.routes = routes
        self.buses = normalizedBuses
        self.sendBusA = sendBusA.normalized(expectedID: .sendA)
        self.sendBusB = sendBusB.normalized(expectedID: .sendB)
        self.masterBus = masterBus.normalized()
        self.patternBanks = normalized.patternBanks
        self.sliceSetPool = sliceSetPool
        self.selectedTrackID = normalized.selectedTrackID
        self.phrases = normalized.phrases
        self.selectedPhraseID = normalized.selectedPhraseID
        syncPhrasesWithTracks()
    }
}

extension Project {
    @discardableResult
    mutating func addMixerBus(name: String? = nil, color: String? = nil) -> UUID {
        let bus = MixerBus(name: resolvedNewMixerBusName(name), color: color)
        buses.append(bus)
        return bus.id
    }

    mutating func renameMixerBus(id: UUID, name: String) {
        guard let index = buses.firstIndex(where: { $0.id == id }) else { return }
        buses[index] = buses[index].renamed(name)
    }

    mutating func setMixerBusColor(_ color: String?, id: UUID) {
        guard let index = buses.firstIndex(where: { $0.id == id }) else { return }
        buses[index].color = MixerBus.normalizedColor(color)
    }

    mutating func setMixerBusMix(id: UUID, mix: BusMixSettings) {
        guard let index = buses.firstIndex(where: { $0.id == id }) else { return }
        buses[index].mix = mix.normalized()
    }

    mutating func updateMixerBusMix(id: UUID, _ update: (inout BusMixSettings) -> Void) {
        guard let index = buses.firstIndex(where: { $0.id == id }) else { return }
        update(&buses[index].mix)
        buses[index].mix = buses[index].mix.normalized()
    }

    mutating func setTrackOutputBus(trackID: UUID, busID: UUID?) {
        guard busID == nil || buses.contains(where: { $0.id == busID }) else { return }
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        tracks[index].outputBusID = busID
    }

    mutating func setTrackSoloed(_ soloed: Bool, trackID: UUID) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        tracks[index].mix.isSoloed = soloed
    }

    mutating func clearAllSolo() {
        for index in tracks.indices {
            tracks[index].mix.isSoloed = false
        }
        for index in buses.indices {
            buses[index].mix.isSoloed = false
        }
    }

    @discardableResult
    mutating func deleteMixerBus(id: UUID) -> [UUID] {
        guard buses.contains(where: { $0.id == id }) else { return [] }
        let affectedTrackIDs = trackIDsRouted(to: id)
        buses.removeAll { $0.id == id }
        for index in tracks.indices where tracks[index].outputBusID == id {
            tracks[index].outputBusID = nil
        }
        return affectedTrackIDs
    }

    func trackIDsRouted(to busID: UUID) -> [UUID] {
        tracks.filter { $0.outputBusID == busID }.map(\.id)
    }

    func mixerBus(id: UUID) -> MixerBus? {
        buses.first { $0.id == id }
    }

    func sendBus(id: SendBusID) -> SendBusState {
        switch id {
        case .sendA:
            return sendBusA.normalized(expectedID: .sendA)
        case .sendB:
            return sendBusB.normalized(expectedID: .sendB)
        }
    }

    mutating func updateSendBus(id: SendBusID, _ update: (inout SendBusState) -> Void) {
        switch id {
        case .sendA:
            update(&sendBusA)
            sendBusA = sendBusA.normalized(expectedID: .sendA)
        case .sendB:
            update(&sendBusB)
            sendBusB = sendBusB.normalized(expectedID: .sendB)
        }
    }

    mutating func setSendBusInserts(_ inserts: [SendBusInsert], id: SendBusID) {
        updateSendBus(id: id) { sendBus in
            sendBus = SendBusState(id: id, inserts: inserts)
        }
    }

    static func tracksByClearingMissingOutputBuses(_ tracks: [StepSequenceTrack], buses: [MixerBus]) -> [StepSequenceTrack] {
        let busIDs = Set(buses.map(\.id))
        return tracks.map { track in
            guard let outputBusID = track.outputBusID, !busIDs.contains(outputBusID) else {
                return track
            }
            var copy = track
            copy.outputBusID = nil
            return copy
        }
    }

    private func resolvedNewMixerBusName(_ requestedName: String?) -> String {
        let existingNames = Set(buses.map(\.name))
        if let requestedName {
            let trimmed = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !existingNames.contains(trimmed) {
                return trimmed
            }
        }

        var index = buses.count + 1
        var candidate = "Bus \(index)"
        while existingNames.contains(candidate) {
            index += 1
            candidate = "Bus \(index)"
        }
        return candidate
    }
}

private extension MixerBus {
    func renamed(_ name: String) -> MixerBus {
        MixerBus(id: id, name: name, color: color, mix: mix, inserts: inserts)
    }
}
