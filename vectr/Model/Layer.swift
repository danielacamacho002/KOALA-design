//
//  Layer.swift
//  vectr
//

import Foundation

struct Layer: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var isVisible: Bool = true
    var isLocked: Bool = false
    /// Optional folder membership. `nil` means the layer sits at the top level.
    /// Layers sharing a `groupID` are kept contiguous in the document's `layers`
    /// array so a folder is always a solid run in the stacking order.
    var groupID: UUID? = nil

    init(id: UUID = UUID(), name: String, isVisible: Bool = true, isLocked: Bool = false, groupID: UUID? = nil) {
        self.id = id
        self.name = name
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.groupID = groupID
    }
}
