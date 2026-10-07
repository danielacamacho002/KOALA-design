//
//  DocumentQueries.swift
//  Koala
//

import CoreGraphics
import Foundation

/// Shared visibility / print-layout queries used by both the live document
/// and an immutable `DocumentSnapshot` so export and raster can run off-main
/// without copying `referenceImageData` on every canvas query.
nonisolated enum DocumentQueries: Sendable {
    static func layerIndexByID(_ layers: [Layer]) -> [UUID: Int] {
        Dictionary(uniqueKeysWithValues: layers.enumerated().map { ($1.id, $0) })
    }

    static func visibleStrokes(layers: [Layer], strokes: [VectorStroke]) -> [VectorStroke] {
        let order = layerIndexByID(layers)
        let visibleLayerIDs = Set(layers.filter(\.isVisible).map(\.id))
        return strokes
            .enumerated()
            .filter { visibleLayerIDs.contains($0.element.layerID) && !$0.element.isHiddenFromCanvas }
            .sorted { lhs, rhs in
                let l = order[lhs.element.layerID] ?? 0
                let r = order[rhs.element.layerID] ?? 0
                return l == r ? lhs.offset < rhs.offset : l < r
            }
            .map(\.element)
    }

    static func visibleTextElements(layers: [Layer], textElements: [TextElement]) -> [TextElement] {
        let order = layerIndexByID(layers)
        let visibleLayerIDs = Set(layers.filter(\.isVisible).map(\.id))
        return textElements
            .enumerated()
            .filter { visibleLayerIDs.contains($0.element.layerID) && !$0.element.isHidden }
            .sorted { lhs, rhs in
                let l = order[lhs.element.layerID] ?? 0
                let r = order[rhs.element.layerID] ?? 0
                return l == r ? lhs.offset < rhs.offset : l < r
            }
            .map(\.element)
    }

    static func visibleReferenceImages(layers: [Layer], images: [ReferenceImage]) -> [ReferenceImage] {
        let order = layerIndexByID(layers)
        let visibleLayerIDs = Set(layers.filter(\.isVisible).map(\.id))
        return images
            .enumerated()
            .filter { visibleLayerIDs.contains($0.element.layerID) }
            .sorted { lhs, rhs in
                let l = order[lhs.element.layerID] ?? 0
                let r = order[rhs.element.layerID] ?? 0
                return l == r ? lhs.offset < rhs.offset : l < r
            }
            .map(\.element)
    }

    /// Images whose `layerID` is missing or unknown are rebound to `fallback`.
    static func bindReferenceImages(
        _ images: [ReferenceImage],
        layers: [Layer],
        fallback: UUID
    ) -> [ReferenceImage] {
        let known = Set(layers.map(\.id))
        return images.map { image in
            guard known.contains(image.layerID) else {
                var copy = image
                copy.layerID = fallback
                return copy
            }
            return image
        }
    }

    static func opacity(layers: [Layer], forLayerID id: UUID) -> CGFloat {
        layers.first { $0.id == id }?.resolvedOpacity ?? 1
    }

    static func printLayoutStrokes(
        layers: [Layer],
        strokes: [VectorStroke],
        printPieces: [VectorStroke],
        printHiddenStrokeIDs: Set<UUID>
    ) -> [VectorStroke] {
        let visibleLayerIDs = Set(layers.filter(\.isVisible).map(\.id))
        var result = visibleStrokes(layers: layers, strokes: strokes)
            .filter { !printHiddenStrokeIDs.contains($0.id) }
        result.append(contentsOf: printPieces.filter { visibleLayerIDs.contains($0.layerID) })
        return result
    }

    static func effectivePrintTransform(
        printStrokeTransforms: [UUID: PrintStrokeTransform],
        contentOffset: CGPoint,
        for strokeID: UUID
    ) -> PrintStrokeTransform {
        var transform = printStrokeTransforms[strokeID] ?? .identity
        transform.translation = CGPoint(
            x: transform.translation.x + contentOffset.x,
            y: transform.translation.y + contentOffset.y
        )
        return transform
    }
}

extension DocumentSnapshot {
    nonisolated func visibleStrokes() -> [VectorStroke] {
        DocumentQueries.visibleStrokes(layers: layers, strokes: strokes)
    }

    nonisolated func visibleTextElements() -> [TextElement] {
        DocumentQueries.visibleTextElements(layers: layers, textElements: textElements)
    }

    /// Current rasters, migrating a legacy single-image document when needed.
    /// Images whose `layerID` is missing or unknown are rebound to `activeLayerID`.
    nonisolated func resolvedReferenceImages() -> [ReferenceImage] {
        let unbound: [ReferenceImage]
        if let images = referenceImages, !images.isEmpty {
            unbound = images
        } else if let data = referenceImageData {
            unbound = [ReferenceImage(data: data, frame: referenceImageFrame ?? .zero)]
        } else {
            unbound = []
        }
        return DocumentQueries.bindReferenceImages(unbound, layers: layers, fallback: activeLayerID)
    }

    nonisolated func visibleReferenceImages() -> [ReferenceImage] {
        DocumentQueries.visibleReferenceImages(layers: layers, images: resolvedReferenceImages())
    }

    nonisolated func opacity(forLayerID id: UUID) -> CGFloat {
        DocumentQueries.opacity(layers: layers, forLayerID: id)
    }

    nonisolated func printLayoutStrokes() -> [VectorStroke] {
        DocumentQueries.printLayoutStrokes(
            layers: layers,
            strokes: strokes,
            printPieces: printPieces,
            printHiddenStrokeIDs: printHiddenStrokeIDs
        )
    }

    nonisolated func effectivePrintTransform(for strokeID: UUID) -> PrintStrokeTransform {
        DocumentQueries.effectivePrintTransform(
            printStrokeTransforms: printStrokeTransforms,
            contentOffset: printLayout.contentOffset,
            for: strokeID
        )
    }

    nonisolated func layerGroup(with id: UUID) -> LayerGroup? {
        layerGroups.first { $0.id == id }
    }
}
