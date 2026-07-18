//
//  ObjectGroup.swift
//  vectr
//

import Foundation

/// A purely structural container ("GroupNode") that references a set of strokes
/// and text elements as a single unit. Members remain independent entities in the
/// document's `strokes`/`textElements` arrays; the group only stores their IDs so
/// grouping never modifies underlying vector coordinates or path commands.
struct ObjectGroup: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var strokeIDs: [UUID]
    var textIDs: [UUID]

    init(id: UUID = UUID(), strokeIDs: [UUID] = [], textIDs: [UUID] = []) {
        self.id = id
        self.strokeIDs = strokeIDs
        self.textIDs = textIDs
    }

    var memberCount: Int { strokeIDs.count + textIDs.count }

    func containsStroke(_ id: UUID) -> Bool { strokeIDs.contains(id) }
    func containsText(_ id: UUID) -> Bool { textIDs.contains(id) }
}
