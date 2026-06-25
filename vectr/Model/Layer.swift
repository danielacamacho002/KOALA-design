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

    init(id: UUID = UUID(), name: String, isVisible: Bool = true, isLocked: Bool = false) {
        self.id = id
        self.name = name
        self.isVisible = isVisible
        self.isLocked = isLocked
    }
}
