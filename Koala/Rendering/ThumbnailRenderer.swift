//
//  ThumbnailRenderer.swift
//  Koala
//

import UIKit

enum ThumbnailRenderer {
    nonisolated static let thumbnailSize = CGSize(width: 400, height: 300)

    static func generate(for document: KoalaDocument) -> UIImage? {
        DocumentRenderer.renderImage(snapshot: document.makeSnapshot(), options: renderOptions)
    }

    static func writeThumbnail(for document: KoalaDocument, to url: URL) throws {
        try writeThumbnail(for: document.makeSnapshot(), to: url)
    }

    nonisolated static func writeThumbnail(for snapshot: DocumentSnapshot, to url: URL) throws {
        guard let image = DocumentRenderer.renderImage(
            snapshot: snapshot,
            options: renderOptions
        ), let data = image.pngData() else {
            throw ThumbnailError.renderFailed
        }
        try data.write(to: url, options: .atomic)
    }

    enum ThumbnailError: Error {
        case renderFailed
    }

    /// Clear background, artwork fitted edge to edge. The gallery card paints the
    /// canvas color behind this image, so light strokes stay visible.
    nonisolated private static let renderOptions = DocumentRenderer.Options(
        size: thumbnailSize,
        drawGrid: false,
        padding: 16,
        fillsBackground: false,
        fitMinScale: ViewportTransform.minScale,
        tightFit: true,
        minimumStrokeWidth: 1.5
    )
}
