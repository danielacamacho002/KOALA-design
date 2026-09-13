//
//  ExportRouter.swift
//  vectr
//

import Foundation

enum ExportRouter {
    static func export(
        document: VectrDocument,
        format: ExportFormat,
        to url: URL,
        quality: ExportQuality = .medium
    ) throws {
        try export(snapshot: document.makeSnapshot(), format: format, to: url, quality: quality)
    }

    nonisolated static func export(
        snapshot: DocumentSnapshot,
        format: ExportFormat,
        to url: URL,
        quality: ExportQuality = .medium
    ) throws {
        switch format {
        case .vectr:
            try DocumentCodec.write(snapshot, to: url)
        case .jpeg:
            try JPEGExporter.write(snapshot: snapshot, to: url, quality: quality)
        case .pdf:
            try PDFExporter.write(snapshot: snapshot, to: url)
        case .svg:
            try SVGExporter.write(snapshot: snapshot, to: url)
        case .ai:
            try PDFExporter.write(snapshot: snapshot, to: url)
        }
    }

    static func temporaryExportURL(
        document: VectrDocument,
        name: String,
        format: ExportFormat,
        quality: ExportQuality = .medium
    ) throws -> URL {
        try temporaryExportURL(snapshot: document.makeSnapshot(), name: name, format: format, quality: quality)
    }

    nonisolated static func temporaryExportURL(
        snapshot: DocumentSnapshot,
        name: String,
        format: ExportFormat,
        quality: ExportQuality = .medium
    ) throws -> URL {
        let temp = FileManager.default.temporaryDirectory
        let fileName = "\(name).\(format.fileExtension)"
        let url = temp.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try export(snapshot: snapshot, format: format, to: url, quality: quality)
        return url
    }

    static func exportProject(
        at fileURL: URL,
        name: String,
        format: ExportFormat,
        to destination: URL,
        quality: ExportQuality = .medium
    ) throws {
        let snapshot = try DocumentCodec.readSnapshot(from: fileURL)
        try export(snapshot: snapshot, format: format, to: destination, quality: quality)
    }
}
