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
    /// Radians about the frame center. Positive rotation matches the move-tool text and stroke handles.
    var rotation: CGFloat = 0
    /// Opacity of this image, multiplied by its layer opacity when drawn. `1` is fully opaque.
    var opacity: CGFloat = 1
    /// When `true`, omitted from canvas, hit-testing, and export.
    /// Optional so older documents without this key still decode.
    var isHidden: Bool? = nil

    var center: CGPoint {
        CGPoint(x: frame.midX, y: frame.midY)
    }

    func corners() -> [CGPoint] {
        let base = [
            CGPoint(x: frame.minX, y: frame.minY),
            CGPoint(x: frame.maxX, y: frame.minY),
            CGPoint(x: frame.maxX, y: frame.maxY),
            CGPoint(x: frame.minX, y: frame.maxY)
        ]
        guard rotation != 0 else { return base }
        let pivot = center
        return base.map { Self.rotate($0, around: pivot, by: rotation) }
    }

    func contains(_ point: CGPoint) -> Bool {
        guard frame.width > 0, frame.height > 0 else { return false }
        guard rotation != 0 else { return frame.contains(point) }
        return frame.contains(Self.rotate(point, around: center, by: -rotation))
    }

    /// True when this image should be omitted from canvas, hit-testing, and export.
    var isHiddenFromCanvas: Bool { isHidden == true }

    func boundingBox() -> CGRect {
        guard rotation != 0 else { return frame }
        var rect = CGRect.null
        for point in corners() {
            rect = rect.union(CGRect(origin: point, size: .zero))
        }
        return rect
    }

    static func rotate(_ point: CGPoint, around pivot: CGPoint, by radians: CGFloat) -> CGPoint {
        let cosA = cos(radians)
        let sinA = sin(radians)
        let dx = point.x - pivot.x
        let dy = point.y - pivot.y
        return CGPoint(
            x: pivot.x + dx * cosA - dy * sinA,
            y: pivot.y + dx * sinA + dy * cosA
        )
    }

    /// Undo snapshots keep id, layer, frame, rotation, opacity, and hidden state without copying raster bytes.
    func omittingPayload() -> ReferenceImage {
        var copy = self
        copy.data = Data()
        return copy
    }

    private enum CodingKeys: String, CodingKey {
        case id, layerID, data, frame, rotation, opacity, isHidden
    }

    init(
        id: UUID = UUID(),
        layerID: UUID = unassignedLayerID,
        data: Data,
        frame: CGRect,
        rotation: CGFloat = 0,
        opacity: CGFloat = 1,
        isHidden: Bool? = nil
    ) {
        self.id = id
        self.layerID = layerID
        self.data = data
        self.frame = frame
        self.rotation = rotation
        self.opacity = opacity
        self.isHidden = isHidden
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        layerID = try container.decodeIfPresent(UUID.self, forKey: .layerID) ?? Self.unassignedLayerID
        data = try container.decode(Data.self, forKey: .data)
        frame = try container.decode(CGRect.self, forKey: .frame)
        rotation = try container.decodeIfPresent(CGFloat.self, forKey: .rotation) ?? 0
        opacity = try container.decodeIfPresent(CGFloat.self, forKey: .opacity) ?? 1
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(layerID, forKey: .layerID)
        try container.encode(data, forKey: .data)
        try container.encode(frame, forKey: .frame)
        try container.encode(rotation, forKey: .rotation)
        try container.encode(opacity, forKey: .opacity)
        try container.encodeIfPresent(isHidden, forKey: .isHidden)
    }
}
