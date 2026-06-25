//
//  DocumentCodec.swift
//  vectr
//

import Foundation

enum DocumentCodec {
    static let fileExtension = "vectr"

    static func encode(_ document: VectrDocument) throws -> Data {
        let snapshot = DocumentSnapshot(
            layers: document.layers,
            strokes: document.strokes,
            activeLayerID: document.activeLayerID,
            viewport: document.viewport,
            grid: document.grid,
            settings: document.settings,
            strokeWidth: document.strokeWidth,
            strokeColor: document.strokeColor,
            selectedStrokeID: document.selectedStrokeID,
            referenceImageData: document.referenceImageData,
            referenceImageFrame: document.referenceImageFrame,
            printLayout: document.printLayout,
            printStrokeTransforms: document.printStrokeTransforms,
            registrationMarks: document.registrationMarks
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(snapshot)
    }

    static func decode(_ data: Data) throws -> VectrDocument {
        let decoder = JSONDecoder()
        let snapshot = try decoder.decode(DocumentSnapshot.self, from: data)
        return VectrDocument(snapshot: snapshot)
    }

    static func write(_ document: VectrDocument, to url: URL) throws {
        let data = try encode(document)
        try data.write(to: url, options: .atomic)
    }

    static func read(from url: URL) throws -> VectrDocument {
        let data = try Data(contentsOf: url)
        return try decode(data)
    }
}
