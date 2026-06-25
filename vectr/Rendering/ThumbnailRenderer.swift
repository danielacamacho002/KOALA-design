//
//  ThumbnailRenderer.swift
//  vectr
//

import UIKit

enum ThumbnailRenderer {
    static let thumbnailSize = CGSize(width: 400, height: 300)

    static func generate(for document: VectrDocument) -> UIImage? {
        DocumentRenderer.renderImage(
            document: document,
            options: DocumentRenderer.Options(size: thumbnailSize, drawGrid: false)
        )
    }

    static func writeThumbnail(for document: VectrDocument, to url: URL) throws {
        guard let image = generate(for: document),
              let data = image.pngData() else {
            throw ThumbnailError.renderFailed
        }
        try data.write(to: url, options: .atomic)
    }

    enum ThumbnailError: Error {
        case renderFailed
    }
}
