//
//  JPEGExporter.swift
//  vectr
//

import UIKit

enum JPEGExporter {
    static func write(document: VectrDocument, to url: URL, quality: CGFloat = 0.92) throws {
        let size = CGSize(width: 2048, height: 1536)
        guard let image = DocumentRenderer.renderImage(
            document: document,
            options: DocumentRenderer.Options(size: size, drawGrid: false)
        ), let data = image.jpegData(compressionQuality: quality) else {
            throw ExportError.renderFailed
        }
        try data.write(to: url, options: .atomic)
    }

    enum ExportError: Error {
        case renderFailed
    }
}
