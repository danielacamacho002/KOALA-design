//
//  JPEGExporter.swift
//  Koala
//

import UIKit

enum JPEGExporter {
    static func write(
        document: KoalaDocument,
        to url: URL,
        quality: ExportQuality = .medium
    ) throws {
        try write(snapshot: document.makeSnapshot(), to: url, quality: quality)
    }

    /// Renders and writes a shareable JPEG into Caches, returning JPEG bytes
    /// (rebuild `UIImage` on the MainActor for Save Image) and the file URL.
    static func prepareForSharing(
        document: KoalaDocument,
        named name: String,
        quality: ExportQuality = .medium
    ) throws -> (jpegData: Data, fileURL: URL) {
        try prepareForSharing(snapshot: document.makeSnapshot(), named: name, quality: quality)
    }

    nonisolated static func write(
        snapshot: DocumentSnapshot,
        to url: URL,
        quality: ExportQuality = .medium
    ) throws {
        let jpegData = try jpegData(snapshot: snapshot, quality: quality)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try jpegData.write(to: url, options: .atomic)
    }

    nonisolated static func prepareForSharing(
        snapshot: DocumentSnapshot,
        named name: String,
        quality: ExportQuality = .medium
    ) throws -> (jpegData: Data, fileURL: URL) {
        let jpegData = try jpegData(snapshot: snapshot, quality: quality)
        let fileURL = cacheURL(named: name)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        try jpegData.write(to: fileURL, options: .atomic)
        return (jpegData, fileURL)
    }

    private nonisolated static func jpegData(
        snapshot: DocumentSnapshot,
        quality: ExportQuality
    ) throws -> Data {
        let size = renderSize(for: snapshot, quality: quality)
        guard let image = DocumentRenderer.renderImage(
            snapshot: snapshot,
            options: DocumentRenderer.Options(size: size, drawGrid: false)
        ), let data = image.jpegData(compressionQuality: quality.jpegCompression) else {
            throw ExportError.renderFailed
        }
        return data
    }

    private nonisolated static func cacheURL(named name: String) -> URL {
        let safeName = name
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fileName = (safeName.isEmpty ? "Export" : safeName) + ".jpg"
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return directory.appendingPathComponent(fileName)
    }

    private nonisolated static func renderSize(for snapshot: DocumentSnapshot, quality: ExportQuality) -> CGSize {
        let bounds = DocumentRenderer.boundingRect(for: snapshot)
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
