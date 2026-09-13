//
//  ThumbnailRenderer.swift
//  vectr
//

import UIKit

enum ThumbnailRenderer {
    nonisolated static let thumbnailSize = CGSize(width: 400, height: 300)

    static func generate(for document: VectrDocument) -> UIImage? {
        DocumentRenderer.renderImage(
            snapshot: document.makeSnapshot(),
            options: DocumentRenderer.Options(size: thumbnailSize, drawGrid: false)
        )
    }

    static func writeThumbnail(for document: VectrDocument, to url: URL) throws {
        try writeThumbnail(for: document.makeSnapshot(), to: url)
    }

    nonisolated static func writeThumbnail(for snapshot: DocumentSnapshot, to url: URL) throws {
        guard let image = DocumentRenderer.renderImage(
            snapshot: snapshot,
            options: DocumentRenderer.Options(size: thumbnailSize, drawGrid: false)
        ), let data = image.pngData() else {
            throw ThumbnailError.renderFailed
        }
        try data.write(to: url, options: .atomic)
    }

    enum ThumbnailError: Error {
        case renderFailed
    }
}
