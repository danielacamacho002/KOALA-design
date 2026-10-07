//
//  PersistenceWorker.swift
//  Koala
//

import Foundation

/// Serializes encode / raster / file writes off the MainActor.
/// Callers must pass an immutable `DocumentSnapshot`, never a live `KoalaDocument`.
actor PersistenceWorker {
    static let shared = PersistenceWorker()

    func write(snapshot: DocumentSnapshot, to url: URL) async throws {
        try DocumentCodec.write(snapshot, to: url)
    }

    func readSnapshot(from url: URL) async throws -> DocumentSnapshot {
        try DocumentCodec.readSnapshot(from: url)
    }

    func writeThumbnail(snapshot: DocumentSnapshot, to url: URL) async throws {
        try ThumbnailRenderer.writeThumbnail(for: snapshot, to: url)
    }

    func export(
        snapshot: DocumentSnapshot,
        format: ExportFormat,
        quality: ExportQuality,
        to url: URL
    ) async throws {
        try ExportRouter.export(snapshot: snapshot, format: format, to: url, quality: quality)
    }

    func temporaryExportURL(
        snapshot: DocumentSnapshot,
        name: String,
        format: ExportFormat,
        quality: ExportQuality
    ) async throws -> URL {
        try ExportRouter.temporaryExportURL(
            snapshot: snapshot,
            name: name,
            format: format,
            quality: quality
        )
    }

    func prepareJPEGForSharing(
        snapshot: DocumentSnapshot,
        named name: String,
        quality: ExportQuality
    ) async throws -> (jpegData: Data, fileURL: URL) {
        try JPEGExporter.prepareForSharing(snapshot: snapshot, named: name, quality: quality)
    }

    func writeTiledPDF(snapshot: DocumentSnapshot, to url: URL) async throws {
        try TiledPDFExporter.write(snapshot: snapshot, to: url)
    }

    func readFileData(from url: URL) async throws -> Data {
        try Data(contentsOf: url)
    }
}
