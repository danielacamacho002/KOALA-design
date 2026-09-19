import CoreGraphics
import Foundation

/// An imported raster (JPEG, PNG, PDF page, etc.) placed on the design canvas.
nonisolated struct ReferenceImage: Identifiable, Codable, Equatable, Sendable {
    /// Used when a file predates `layerID`; rebound to the active layer on load.
    static let unassignedLayerID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!

    var id: UUID = UUID()
    var layerID: UUID = unassignedLayerID
    var data: Data
    var frame: CGRect

    func corners() -> [CGPoint] {
        [
            CGPoint(x: frame.minX, y: frame.minY),
            CGPoint(x: frame.maxX, y: frame.minY),
            CGPoint(x: frame.maxX, y: frame.maxY),
            CGPoint(x: frame.minX, y: frame.maxY)
        ]
    }

    func contains(_ point: CGPoint) -> Bool {
        frame.width > 0 && frame.height > 0 && frame.contains(point)
    }

    private enum CodingKeys: String, CodingKey {
        case id, layerID, data, frame
    }

    init(id: UUID = UUID(), layerID: UUID = unassignedLayerID, data: Data, frame: CGRect) {
        self.id = id
        self.layerID = layerID
        self.data = data
        self.frame = frame
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        layerID = try container.decodeIfPresent(UUID.self, forKey: .layerID) ?? Self.unassignedLayerID
        data = try container.decode(Data.self, forKey: .data)
        frame = try container.decode(CGRect.self, forKey: .frame)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(layerID, forKey: .layerID)
        try container.encode(data, forKey: .data)
        try container.encode(frame, forKey: .frame)
    }
}
