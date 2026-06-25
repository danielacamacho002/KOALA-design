//
//  ExportRouter.swift
//  vectr
//

import Foundation

enum ExportRouter {
    static func export(document: VectrDocument, format: ExportFormat, to url: URL) throws {
        switch format {
        case .vectr:
            try DocumentCodec.write(document, to: url)
        case .jpeg:
            try JPEGExporter.write(document: document, to: url)
        case .pdf:
            try PDFExporter.write(document: document, to: url)
        case .svg:
            try SVGExporter.write(document: document, to: url)
        case .ai:
            try PDFExporter.write(document: document, to: url)
        }
    }

    static func temporaryExportURL(document: VectrDocument, name: String, format: ExportFormat) throws -> URL {
        let temp = FileManager.default.temporaryDirectory
        let fileName = "\(name).\(format.fileExtension)"
        let url = temp.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try export(document: document, format: format, to: url)
        return url
    }

    static func exportProject(at fileURL: URL, name: String, format: ExportFormat, to destination: URL) throws {
        let document = try DocumentCodec.read(from: fileURL)
        try export(document: document, format: format, to: destination)
    }
}
