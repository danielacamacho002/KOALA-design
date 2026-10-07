//
//  DocumentCodec.swift
//  Koala
//

import Foundation

enum DocumentCodec {
    nonisolated static let fileExtension = "vectr"

    static func encode(_ document: KoalaDocument) throws -> Data {
        try encode(document.makeSnapshot())
    }

    static func decode(_ data: Data) throws -> KoalaDocument {
        KoalaDocument(snapshot: try decodeSnapshot(data))
    }

    static func write(_ document: KoalaDocument, to url: URL) throws {
        try write(document.makeSnapshot(), to: url)
    }

    static func read(from url: URL) throws -> KoalaDocument {
        KoalaDocument(snapshot: try readSnapshot(from: url))
    }

    nonisolated static func encode(_ snapshot: DocumentSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(snapshot)
    }

    nonisolated static func decodeSnapshot(_ data: Data) throws -> DocumentSnapshot {
        let decoder = JSONDecoder()
        return try decoder.decode(DocumentSnapshot.self, from: data)
    }

    nonisolated static func write(_ snapshot: DocumentSnapshot, to url: URL) throws {
        let data = try encode(snapshot)
        try data.write(to: url, options: .atomic)
    }

    nonisolated static func readSnapshot(from url: URL) throws -> DocumentSnapshot {
        let data = try Data(contentsOf: url)
        return try decodeSnapshot(data)
    }
}
