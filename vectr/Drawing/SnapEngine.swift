//
//  SnapEngine.swift
//  vectr
//

import CoreGraphics
import Foundation

struct SnapResult {
    var point: CGPoint
    var didSnap: Bool
}

func snapPointToGrid(_ point: CGPoint, gridSpacing: CGFloat) -> CGPoint {
    guard gridSpacing > 0 else { return point }
    return CGPoint(
        x: (point.x / gridSpacing).rounded() * gridSpacing,
        y: (point.y / gridSpacing).rounded() * gridSpacing
    )
}

func snapDrawingPoint(
    _ point: CGPoint,
    grid: GridSettings,
    settings: DocumentSettings,
    enabled: Bool
) -> CGPoint {
    guard enabled, grid.snapEnabled else { return point }
    let spacing = grid.visualSpacing(for: settings)
    return snapPointToGrid(point, gridSpacing: spacing)
}

func snapDrawingControlPoint(
    raw: CGPoint,
    projected: CGPoint,
    grid: GridSettings,
    settings: DocumentSettings,
    enabled: Bool
) -> CGPoint {
    snapDrawingPoint(projected, grid: grid, settings: settings, enabled: enabled)
}

struct SnapEngine {
    var grid: GridSettings
    var existingStrokes: [VectorStroke]
    var enabled: Bool
    var constraints: ConstraintSettings = ConstraintSettings()
    var documentSettings: DocumentSettings = DocumentSettings()

    func snap(
        point: CGPoint,
        referenceStart: CGPoint? = nil
    ) -> SnapResult {
        guard enabled else { return SnapResult(point: point, didSnap: false) }

        var snapped = point
        var didSnap = false

        if grid.snapEnabled {
            let gridPoint = snapPointToGrid(
                point,
                gridSpacing: grid.visualSpacing(for: documentSettings)
            )
            if gridPoint != point {
                snapped = gridPoint
                didSnap = true
            }
        }

        if let objectSnap = snapToObjects(snapped) {
            snapped = objectSnap
            didSnap = true
        }

        if constraints.perpendicularEnabled, let start = referenceStart {
            let perp = snapPerpendicular(from: start, to: snapped)
            if perp != snapped {
                snapped = perp
                didSnap = true
            }
        } else if grid.angleSnapEnabled, let start = referenceStart {
            let angleSnapped = snapAngle(from: start, to: snapped, tolerance: 6)
            if angleSnapped != snapped {
                snapped = angleSnapped
                didSnap = true
            }
        }

        return SnapResult(point: snapped, didSnap: didSnap)
    }

    func snapToGrid(_ point: CGPoint, documentSettings: DocumentSettings) -> CGPoint {
        snapPointToGrid(point, gridSpacing: grid.visualSpacing(for: documentSettings))
    }

    func snapToObjects(_ point: CGPoint, threshold: CGFloat = 12) -> CGPoint? {
        var best: CGPoint?
        var bestDistance = threshold

        for stroke in existingStrokes {
            for anchor in snapAnchors(for: stroke) {
                let distance = hypot(point.x - anchor.x, point.y - anchor.y)
                if distance < bestDistance {
                    bestDistance = distance
                    best = anchor
                }
            }
        }
        return best
    }

    func snapPerpendicular(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = hypot(dx, dy)
        guard distance > 0 else { return end }

        let angleRadians = atan2(dy, dx)
        let angleDegrees = angleRadians * 180 / .pi
        let targets: [CGFloat] = [90, 270, -90]
        for target in targets {
            if abs(angleDegrees - target) < 12 || abs(angleDegrees - target - 360) < 12 {
                let radians = target * .pi / 180
                return CGPoint(
                    x: start.x + cos(radians) * distance,
                    y: start.y + sin(radians) * distance
                )
            }
        }
        return end
    }

    func snapAngle(from start: CGPoint, to end: CGPoint, tolerance: CGFloat = 8) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = hypot(dx, dy)
        guard distance > 0 else { return end }

        let angleRadians = atan2(dy, dx)
        let angleDegrees = angleRadians * 180 / .pi

        for target in grid.angleSnapDegrees {
            if abs(angleDegrees - target) < tolerance ||
                abs(angleDegrees - target - 360) < tolerance ||
                abs(angleDegrees - target + 360) < tolerance {
                let radians = target * .pi / 180
                return CGPoint(
                    x: start.x + cos(radians) * distance,
                    y: start.y + sin(radians) * distance
                )
            }
        }
        return end
    }

    private func snapAnchors(for stroke: VectorStroke) -> [CGPoint] {
        var anchors: [CGPoint] = []
        if constraints.coincidentEnabled {
            anchors.append(contentsOf: stroke.points)
        }
        if constraints.midpointEnabled, stroke.points.count >= 2 {
            let count = stroke.isClosed ? stroke.points.count : stroke.points.count - 1
            for index in 0..<count {
                let a = stroke.points[index]
                let b = stroke.points[(index + 1) % stroke.points.count]
                anchors.append(CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2))
            }
        } else if stroke.points.count >= 2 {
            for index in 0..<(stroke.points.count - 1) {
                let a = stroke.points[index]
                let b = stroke.points[index + 1]
                anchors.append(CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2))
            }
        }
        return anchors
    }
}
