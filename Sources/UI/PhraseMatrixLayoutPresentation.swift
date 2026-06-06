import SwiftUI

enum PhraseMatrixPageDirection: Equatable {
    case previous
    case next
}

struct PhraseMatrixPageArrowPresentation: Equatable {
    let direction: PhraseMatrixPageDirection
    let isEnabled: Bool
    let adjacentTrackCount: Int

    var occupancyHint: String? {
        adjacentTrackCount > 0 ? "\(adjacentTrackCount)" : nil
    }

    var accessibilityLabel: String {
        let directionLabel = direction == .previous ? "Previous track page" : "Next track page"
        guard isEnabled else {
            return "\(directionLabel), unavailable"
        }
        guard let occupancyHint else {
            return "\(directionLabel), no adjacent tracks"
        }
        return "\(directionLabel), \(occupancyHint) tracks"
    }
}

struct PhraseMatrixLayoutPresentation: Equatable {
    static let trackPageSize = 8
    static let matrixGutterWidth: CGFloat = 34
    static let layerSelectorWidth: CGFloat = 260
    static let selectableLayerIDs = ["pattern", "transpose", "variance", "fx-send", "mute"]

    let trackCount: Int
    let pageIndex: Int
    let pageSize: Int

    init(
        trackCount: Int,
        pageIndex: Int,
        pageSize: Int = Self.trackPageSize
    ) {
        self.trackCount = max(0, trackCount)
        self.pageSize = max(1, pageSize)
        let maxPageIndex = max(0, Int(ceil(Double(max(0, trackCount)) / Double(max(1, pageSize)))) - 1)
        self.pageIndex = min(max(pageIndex, 0), maxPageIndex)
    }

    var pageCount: Int {
        max(1, Int(ceil(Double(trackCount) / Double(pageSize))))
    }

    func arrow(for direction: PhraseMatrixPageDirection) -> PhraseMatrixPageArrowPresentation {
        let adjacentIndex = direction == .previous ? pageIndex - 1 : pageIndex + 1
        let adjacentCount = trackCount(onPage: adjacentIndex)
        return PhraseMatrixPageArrowPresentation(
            direction: direction,
            isEnabled: adjacentCount > 0,
            adjacentTrackCount: adjacentCount
        )
    }

    private func trackCount(onPage page: Int) -> Int {
        guard page >= 0, page < pageCount else {
            return 0
        }
        let startIndex = page * pageSize
        guard startIndex < trackCount else {
            return 0
        }
        return min(pageSize, trackCount - startIndex)
    }
}

struct PhraseLayerSelectorPresentation: Equatable {
    static let fixedOuterWidth = PhraseMatrixLayoutPresentation.layerSelectorWidth
    static let lineLimit = 1

    let layerName: String
    let subtitle: String
    let indexLabel: String

    var displayName: String {
        layerName.uppercased()
    }

    var accessibilityLabel: String {
        "\(layerName), \(subtitle), \(indexLabel)"
    }

    static func selectableLayers(from layers: [PhraseLayerDefinition]) -> [PhraseLayerDefinition] {
        Self.selectableLayerIDs.compactMap { layerID in
            layers.first { $0.id == layerID }
        }
    }

    static var selectableLayerIDs: [String] {
        PhraseMatrixLayoutPresentation.selectableLayerIDs
    }

    static func displayName(for layer: PhraseLayerDefinition) -> String {
        layer.id == "variance" ? "Variance %" : layer.name
    }
}
