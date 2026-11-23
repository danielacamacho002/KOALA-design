//
//  Layer.swift
//  Koala
//

import CoreGraphics
import Foundation

nonisolated struct Layer: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var name: String
    var isVisible: Bool = true
    var isLocked: Bool = false
    /// Optional folder membership. `nil` means the layer sits at the top level.
    /// Layers sharing a `groupID` are kept contiguous in the document's `layers`
    /// array so a folder is always a solid run in the stacking order.
    var groupID: UUID? = nil
    /// Visual alpha for the layer's contents, independent of `isVisible`.
    var opacity: CGFloat = 1

    /// Opacity clamped to 0...1.
    var resolvedOpacity: CGFloat { min(1, max(0, opacity)) }

    init(
        id: UUID = UUID(),
        name: String,
        isVisible: Bool = true,
        isLocked: Bool = false,
        groupID: UUID? = nil,
        opacity: CGFloat = 1
    ) {
        self.id = id
        self.name = name
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.groupID = groupID
        self.opacity = opacity
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, isVisible, isLocked, groupID, opacity
    }

    // Custom decoding so projects saved before layer opacity still open.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isVisible = try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
        isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        groupID = try container.decodeIfPresent(UUID.self, forKey: .groupID)
        opacity = try container.decodeIfPresent(CGFloat.self, forKey: .opacity) ?? 1
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(isVisible, forKey: .isVisible)
        try container.encode(isLocked, forKey: .isLocked)
        try container.encodeIfPresent(groupID, forKey: .groupID)
        try container.encode(opacity, forKey: .opacity)
    }
}
