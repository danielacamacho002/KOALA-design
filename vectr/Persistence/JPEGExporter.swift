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
        try write(image: image, to: url, quality: quality)
    }

    /// Renders and writes a shareable JPEG into Caches, returning both the image
    /// (for Save Image) and the file URL (for AirDrop / Files).
    static func prepareForSharing(
        document: VectrDocument,
        named name: String,
        quality: ExportQuality = .medium
    ) throws -> (image: UIImage, fileURL: URL) {
        let image = try renderImage(document: document, quality: quality)
        let fileURL = cacheURL(named: name)
        try write(image: image, to: fileURL, quality: quality)
        return (image, fileURL)
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

    private static func write(image: UIImage, to url: URL, quality: ExportQuality) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        guard let data = image.jpegData(compressionQuality: quality.jpegCompression) else {
            throw ExportError.renderFailed
        }
        try data.write(to: url, options: .atomic)
    }

    private static func cacheURL(named name: String) -> URL {
        let safeName = name
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fileName = (safeName.isEmpty ? "Export" : safeName) + ".jpg"
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return directory.appendingPathComponent(fileName)
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
