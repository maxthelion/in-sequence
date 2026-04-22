import Foundation

// MARK: - Track macro management

extension Project {

    // MARK: - Built-in sampler macros

    /// Returns the three built-in sampler macro bindings for a given track.
    /// IDs are deterministic — stable across document loads.
    static func builtinSamplerBindings(for trackID: UUID) -> [TrackMacroBinding] {
        BuiltinMacroKind.allCases.map { kind in
            TrackMacroBinding(descriptor: TrackMacroDescriptor.builtin(trackID: trackID, kind: kind))
        }
    }

    /// True if the destination kind should carry sampler built-in macros.
    private static func isSamplerKind(_ destination: Destination) -> Bool {
        switch destination.kind {
        case .internalSampler, .sample:
            return true
        default:
            return false
        }
    }

    // MARK: - Destination transition helper

    /// Assign a destination and update built-in macros to match.
    ///
    /// - When transitioning to `.sample` or `.internalSampler`:
    ///   append the three sampler built-ins if not already present.
    /// - When transitioning to `.auInstrument`:
    ///   remove `.builtin(...)` bindings; preserve `.auParameter(...)` bindings.
    /// - All other destinations: remove sampler built-ins.
    mutating func setDestinationWithMacros(_ destination: Destination, for trackID: UUID) {
        setEditedDestination(destination, for: trackID)
        syncBuiltinMacros(for: trackID, newDestination: destination)
    }

    private mutating func syncBuiltinMacros(for trackID: UUID, newDestination: Destination) {
        guard let trackIndex = tracks.firstIndex(where: { $0.id == trackID }) else {
            return
        }

        if Self.isSamplerKind(newDestination) {
            // Ensure all three built-ins exist; never duplicate.
            let builtins = Self.builtinSamplerBindings(for: trackID)
            for binding in builtins {
                if !tracks[trackIndex].macros.contains(where: { $0.id == binding.id }) {
                    tracks[trackIndex].macros.append(binding)
                }
            }
        } else {
            // Remove built-in bindings (keep auParameter bindings).
            let builtinIDs = Set(BuiltinMacroKind.allCases.map {
                TrackMacroDescriptor.builtinID(trackID: trackID, kind: $0)
            })
            tracks[trackIndex].macros.removeAll { builtinIDs.contains($0.id) }
        }
    }

    // MARK: - Add / remove AU macros

    /// Append an AU macro descriptor to the track. Enforces a cap of 8 bindings.
    /// If a binding with the same descriptor id already exists, this is a no-op.
    @discardableResult
    mutating func addAUMacro(descriptor: TrackMacroDescriptor, to trackID: UUID) -> Bool {
        guard let trackIndex = tracks.firstIndex(where: { $0.id == trackID }) else {
            return false
        }
        guard tracks[trackIndex].macros.count < 8 else {
            return false
        }
        guard !tracks[trackIndex].macros.contains(where: { $0.id == descriptor.id }) else {
            return false // already present — no-op
        }
        tracks[trackIndex].macros.append(TrackMacroBinding(descriptor: descriptor))
        return true
    }

    /// Remove a macro binding by id and cascade into phrase-layer cells and clip lanes.
    mutating func removeMacro(id macroID: UUID, from trackID: UUID) {
        guard let trackIndex = tracks.firstIndex(where: { $0.id == trackID }) else {
            return
        }
        tracks[trackIndex].macros.removeAll { $0.id == macroID }

        // Cascade: drop phrase-layer cells for this binding.
        let layerID = "macro-\(trackID.uuidString)-\(macroID.uuidString)"
        layers.removeAll { $0.id == layerID }
        for phraseIndex in phrases.indices {
            phrases[phraseIndex].cells.removeAll { $0.layerID == layerID }
        }

        // Cascade: drop clip macro lanes that referenced this binding.
        for clipIndex in clipPool.indices {
            clipPool[clipIndex].macroLanes.removeValue(forKey: macroID)
        }
    }

    // MARK: - Layer sync

    /// Re-derive the layer list to include one layer per (track, binding) pair,
    /// appended after the fixed built-in layers.
    mutating func syncMacroLayers() {
        let builtinLayers = PhraseLayerDefinition.defaultSet(for: tracks)
        let builtinLayerIDs = Set(builtinLayers.map(\.id))

        // Compute the desired macro layers.
        let macroLayers = PhraseLayerDefinition.macroLayers(for: tracks)
        let macroLayerIDs = Set(macroLayers.map(\.id))

        // Remove stale macro layers (for removed bindings), keep builtins and new macros.
        let keptLayers = layers.filter { layer in
            builtinLayerIDs.contains(layer.id) || macroLayerIDs.contains(layer.id)
        }

        // Merge: builtins first (sync their defaults), then macros.
        let mergedBuiltins = builtinLayers.map { newLayer -> PhraseLayerDefinition in
            keptLayers.first(where: { $0.id == newLayer.id }) ?? newLayer
        }
        let mergedMacros = macroLayers.map { newLayer -> PhraseLayerDefinition in
            keptLayers.first(where: { $0.id == newLayer.id }) ?? newLayer
        }
        layers = (mergedBuiltins + mergedMacros).map { $0.synced(with: tracks) }

        // Sync phrases with the updated layer list.
        phrases = phrases.map { $0.synced(with: tracks, layers: layers) }
    }
}
