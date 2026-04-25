import Foundation

// MARK: - Track macro management

extension Project {
    private static let macroSlotCount = 8

    // MARK: - Built-in sampler macros

    /// Returns the three built-in sampler macro bindings for a given track.
    /// IDs are deterministic — stable across document loads.
    static func builtinSamplerBindings(for trackID: UUID) -> [TrackMacroBinding] {
        BuiltinMacroKind.allCases.enumerated().map { index, kind in
            TrackMacroBinding(
                descriptor: TrackMacroDescriptor.builtin(trackID: trackID, kind: kind),
                slotIndex: index
            )
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

        let builtinIDs = Set(BuiltinMacroKind.allCases.map {
            TrackMacroDescriptor.builtinID(trackID: trackID, kind: $0)
        })

        let currentMacros = tracks[trackIndex].macros

        if Self.isSamplerKind(newDestination) {
            // Sampler has exactly 8 built-in slots (BuiltinMacroKind.allCases fills them).
            // AU macros are dropped: there is no room beyond slot 7 without breaking the
            // slotIndex clamp, and the north-star spec does not require AU macro preservation
            // across kind transitions. (Option A from the C2 review critique.)
            //
            // Use removeMacro(id:from:) for every binding that won't survive so that phrase
            // layers and clip macro lanes are cascade-purged (CR2-2 fix).
            let newBuiltinIDs = Set(Self.builtinSamplerBindings(for: trackID).map(\.id))
            for binding in currentMacros where !newBuiltinIDs.contains(binding.id) {
                removeMacro(id: binding.id, from: trackID)
            }
            // Now set the exact built-in set (idempotent for already-present ones).
            guard let updatedTrackIndex = tracks.firstIndex(where: { $0.id == trackID }) else {
                return
            }
            tracks[updatedTrackIndex].macros = Self.builtinSamplerBindings(for: trackID)
        } else {
            // Remove built-in bindings (cascade layers + clip lanes) and compact slots.
            // Keep auParameter bindings; drop any builtin ones.
            let preservedAUMacros = currentMacros.filter { !builtinIDs.contains($0.id) }
            for binding in currentMacros where builtinIDs.contains(binding.id) {
                removeMacro(id: binding.id, from: trackID)
            }
            // Re-compact slot indices on the survivors.
            guard let updatedTrackIndex = tracks.firstIndex(where: { $0.id == trackID }) else {
                return
            }
            tracks[updatedTrackIndex].macros = orderedMacroBindings(preservedAUMacros).enumerated().map { index, binding in
                binding.withSlotIndex(index)
            }
        }
    }

    // MARK: - Add / remove AU macros

    /// Append an AU macro descriptor to the track into a specific slot (0–7).
    /// Enforces a cap of 8 AU bindings and rejects duplicate AU parameter addresses.
    /// When `slotIndex` is nil, picks the first free slot.
    @discardableResult
    mutating func addAUMacro(
        descriptor: TrackMacroDescriptor,
        to trackID: UUID,
        slotIndex: Int? = nil
    ) -> Bool {
        guard let trackIndex = tracks.firstIndex(where: { $0.id == trackID }) else {
            return false
        }
        var macros = orderedMacroBindings(tracks[trackIndex].macros)
        let auMacros = macros.filter {
            if case .auParameter = $0.source { return true }
            return false
        }
        guard auMacros.count < Self.macroSlotCount else {
            return false
        }
        guard !macros.contains(where: { $0.id == descriptor.id }) else {
            return false // already present — no-op
        }

        // Reject duplicate AU parameter address.
        if case let .auParameter(address, identifier) = descriptor.source,
           auMacros.contains(where: { binding in
               guard case let .auParameter(existingAddress, existingIdentifier) = binding.source else {
                   return false
               }
               return existingAddress == address && existingIdentifier == identifier
           }) {
            return false
        }

        // Include ALL macros (built-in and AU) so that auto-slot selection
        // never picks a slot already occupied by a built-in (C3 fix).
        let occupiedSlots = Set(macros.map(\.slotIndex))
        let resolvedSlot: Int
        if let slotIndex {
            guard (0..<Self.macroSlotCount).contains(slotIndex),
                  !occupiedSlots.contains(slotIndex)
            else {
                return false
            }
            resolvedSlot = slotIndex
        } else if let next = (0..<Self.macroSlotCount).first(where: { !occupiedSlots.contains($0) }) {
            resolvedSlot = next
        } else {
            return false
        }

        macros.append(TrackMacroBinding(descriptor: descriptor, slotIndex: resolvedSlot))
        tracks[trackIndex].macros = orderedMacroBindings(macros)
        return true
    }

    /// Remove a macro binding by id and cascade into phrase-layer cells and clip lanes.
    mutating func removeMacro(id macroID: UUID, from trackID: UUID) {
        guard let trackIndex = tracks.firstIndex(where: { $0.id == trackID }) else {
            return
        }
        tracks[trackIndex].macros.removeAll { $0.id == macroID }
        tracks[trackIndex].macros = orderedMacroBindings(tracks[trackIndex].macros)

        // Cascade: drop phrase-layer cells for this binding.
        let layerID = "macro-\(trackID.uuidString)-\(macroID.uuidString)"
        layers.removeAll { $0.id == layerID }
        for phraseIndex in phrases.indices {
            phrases[phraseIndex].cells.removeAll { $0.layerID == layerID }
        }

        // Cascade: drop clip macro lanes that referenced this binding.
        for clipIndex in clipPool.indices {
            clipPool[clipIndex] = clipPool[clipIndex].removingMacroLane(id: macroID)
        }
    }

    // MARK: - Live value application

    /// Write a live macro value into the phrase layer default for `trackID`.
    ///
    /// This is the "live knob drag" path: it sets the default that will be used
    /// when the phrase cell is `.inheritDefault`, without touching any existing
    /// step/bar/single cells. This keeps arrangement-level automation intact.
    mutating func setMacroLayerDefault(value: Double, bindingID: UUID, trackID: UUID, phraseID: UUID) {
        let layerID = "macro-\(trackID.uuidString)-\(bindingID.uuidString)"
        guard let layerIndex = layers.firstIndex(where: { $0.id == layerID }) else {
            return
        }
        layers[layerIndex].defaults[trackID] = .scalar(value)

        // Also update phrase cells that are .inheritDefault so they pick up
        // the new value when the coordinator resolves them. Cells with explicit
        // values are NOT changed.
        // (No explicit phrase-cell change needed — coordinator reads defaults at
        //  resolve time when cell == .inheritDefault. No doc mutation required.)
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

    private func orderedMacroBindings(_ macros: [TrackMacroBinding]) -> [TrackMacroBinding] {
        macros.sorted { lhs, rhs in
            if lhs.slotIndex != rhs.slotIndex {
                return lhs.slotIndex < rhs.slotIndex
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }
}
