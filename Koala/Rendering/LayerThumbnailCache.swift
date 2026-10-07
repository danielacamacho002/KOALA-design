//
//  LayerThumbnailCache.swift
//  Koala
//

import CoreGraphics
import UIKit

/// Memoizes `LayerThumbnailRenderer` output so the layers panel only rasterizes
/// a preview when that layer's own content actually changed.
///
/// `VectorStroke`, `TextElement`, and `ReferenceImage` are `Equatable` but not `Hashable`, so the
/// cache keeps the exact inputs it last drew and compares them instead of
/// hashing. Equality short-circuits on the first difference, making the
/// unchanged-layer path far cheaper than a redraw.
@MainActor
final class LayerThumbnailCache {
    static let shared = LayerThumbnailCache()

    private struct Entry {
        var strokes: [VectorStroke]
        var texts: [TextElement]
        var images: [ReferenceImage]
        var size: CGSize
        var isDark: Bool
        var image: UIImage?
    }

    /// Keyed by layer ID. Layer IDs are UUIDs, so entries left behind by a
    /// previously open project can never collide with a new one.
    private var entries: [UUID: Entry] = [:]
    private let capacity = 64

    private init() {}

    func image(
        document: KoalaDocument,
        layerID: UUID,
        size: CGSize,
        isDark: Bool
    ) -> UIImage? {
        let strokes = document.strokes(for: layerID).filter { !$0.isHiddenFromCanvas }
        let texts = document.textElements.filter { $0.layerID == layerID && !$0.isHidden }
        let images = document.referenceImages(for: layerID)

        if let cached = entries[layerID],
           cached.size == size,
           cached.isDark == isDark,
           cached.strokes == strokes,
           cached.texts == texts,
           cached.images == images {
            return cached.image
        }

        let rendered = LayerThumbnailRenderer.render(
            document: document,
            layerID: layerID,
            size: size
        )

        if entries.count >= capacity, !entries.keys.contains(layerID) {
            entries.removeAll()
        }
        entries[layerID] = Entry(
            strokes: strokes,
            texts: texts,
            images: images,
            size: size,
            isDark: isDark,
            image: rendered
        )
        return rendered
    }
}
