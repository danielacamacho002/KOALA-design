//
//  LayerGroup.swift
//  Koala
//

import Foundation

/// A lightweight layer folder. It only carries presentation state (name and
/// collapsed flag); membership lives on each `Layer` via `groupID`, and
/// visibility/lock/opacity cascade directly onto the member layers' own flags
/// so the flat draw order (and everything that depends on it) stays untouched.
nonisolated struct LayerGroup: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var name: String
    var isCollapsed: Bool = false

    init(id: UUID = UUID(), name: String, isCollapsed: Bool = false) {
        self.id = id
        self.name = name
        self.isCollapsed = isCollapsed
    }
}
