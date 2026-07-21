//
//  JPEGExporter.swift
//  vectr
//

import UIKit

enum JPEGExporter {
    static func write(
        document: VectrDocument,
        to url: URL,
        quality: ExportQuality = .medium
    ) throws {
        let image = try renderImage(document: document, quality: quality)
        guard let data = image.jpegData(compressionQuality: quality.jpegCompression) else {
            throw ExportError.renderFailed
        }
        try data.write(to: url, options: .atomic)
    }

    static func renderImage(
        document: VectrDocument,
        quality: ExportQuality = .medium
    ) throws -> UIImage {
        let size = renderSize(for: document, quality: quality)
        guard let image = DocumentRenderer.renderImage(
            document: document,
            options: DocumentRenderer.Options(size: size, drawGrid: false)
        ) else {
            throw ExportError.renderFailed
        }
        return image
    }

    private static func renderSize(for document: VectrDocument, quality: ExportQuality) -> CGSize {
        let bounds = DocumentRenderer.boundingRect(for: document)
        let width = max(bounds.width, 1)
        let height = max(bounds.height, 1)
        let longEdge = quality.longEdgePixels
        if width >= height {
            let scaledHeight = max(1, (longEdge * height / width).rounded())
            return CGSize(width: longEdge, height: scaledHeight)
        } else {
            let scaledWidth = max(1, (longEdge * width / height).rounded())
            return CGSize(width: scaledWidth, height: longEdge)
        }
    }

    enum ExportError: Error {
        case renderFailed
    }
}
