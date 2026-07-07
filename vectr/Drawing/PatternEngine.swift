//
//  PatternEngine.swift
//  vectr
//

import CoreGraphics
import Foundation

enum PatternEngine {
    private struct Placement {
        var translation: CGPoint
        var rotation: CGFloat
    }

    private static let minimumRadius: CGFloat = 1

    static func defaultSpacing(for stroke: VectorStroke, gap: CGFloat = 4) -> (x: CGFloat, y: CGFloat) {
        let points = ShapeGeometry.renderPoints(for: stroke)
        let rect = PrintLayoutCoordinateSpace.boundingRect(for: points)
        guard !rect.isNull else { return (50, 50) }
        return (max(rect.width + gap, 1), max(rect.height + gap, 1))
    }

    static func generatedCopies(from stroke: VectorStroke, settings: PatternSettings) -> [VectorStroke] {
        let pivot = ShapeGeometry.shapeCenter(for: stroke)
            ?? strokeCenter(from: stroke)
        let placements = computePlacements(settings: settings)
        return placements.map { placement in
            transformedCopy(
                stroke,
                pivot: pivot,
                translation: placement.translation,
                rotation: placement.rotation
            )
        }
    }

    private static func strokeCenter(from stroke: VectorStroke) -> CGPoint {
        let points = ShapeGeometry.renderPoints(for: stroke)
        return PrintLayoutCoordinateSpace.center(of: points)
    }

    private static func computePlacements(settings: PatternSettings) -> [Placement] {
        switch settings.mode {
        case .grid:
            return gridPlacements(settings: settings)
        case .linear:
            return linearPlacements(settings: settings)
        case .radial:
            return radialPlacements(settings: settings)
        case .spiral:
            return spiralPlacements(settings: settings)
        }
    }

    private static func gridPlacements(settings: PatternSettings) -> [Placement] {
        let rows = clamp(settings.rows, min: 1, max: PatternSettings.maxCount)
        let columns = clamp(settings.columns, min: 1, max: PatternSettings.maxCount)
        let total = min(rows * columns, PatternSettings.maxCount)
        var placements: [Placement] = []

        for index in 0..<total {
            let row = index / columns
            let column = index % columns
            if settings.includeOriginal, row == 0, column == 0 { continue }
            placements.append(
                Placement(
                    translation: CGPoint(
                        x: CGFloat(column) * settings.spacingX,
                        y: CGFloat(row) * settings.spacingY
                    ),
                    rotation: 0
                )
            )
        }
        return placements
    }

    private static func linearPlacements(settings: PatternSettings) -> [Placement] {
        let count = clamp(settings.count, min: 1, max: PatternSettings.maxCount)
        var placements: [Placement] = []

        for index in 0..<count {
            if settings.includeOriginal, index == 0 { continue }
            let offset: CGPoint
            switch settings.linearDirection {
            case .horizontal:
                offset = CGPoint(x: CGFloat(index) * settings.spacingX, y: 0)
            case .vertical:
                offset = CGPoint(x: 0, y: CGFloat(index) * settings.spacingY)
            }
            placements.append(Placement(translation: offset, rotation: 0))
        }
        return placements
    }

    private static func radialPlacements(settings: PatternSettings) -> [Placement] {
        let count = clamp(settings.count, min: 1, max: PatternSettings.maxCount)
        let startRadius = max(settings.spacingX, minimumRadius)
        let tightness = max(settings.tightness, minimumRadius)
        var placements: [Placement] = []

        for index in 0..<count {
            if settings.includeOriginal, index == 0 { continue }

            let angle: CGFloat
            if settings.radialSpreadEven {
                angle = CGFloat(index) * (2 * .pi / CGFloat(count))
            } else {
                angle = CGFloat(index) * (tightness / startRadius)
            }

            let translation = CGPoint(
                x: cos(angle) * startRadius,
                y: sin(angle) * startRadius
            )
            let rotation = settings.rotateCopies ? angle : 0
            placements.append(Placement(translation: translation, rotation: rotation))
        }
        return placements
    }

    private static func spiralPlacements(settings: PatternSettings) -> [Placement] {
        let count = clamp(settings.count, min: 1, max: PatternSettings.maxCount)
        let startRadius = max(settings.spacingX, minimumRadius)
        let tightness = max(settings.tightness, minimumRadius)
        let radiusGrowthPerRadian = tightness / (2 * .pi)
        var placements: [Placement] = []

        var angle: CGFloat = 0
        var radius = startRadius
        var placedCount = 0

        for index in 0..<count {
            if settings.includeOriginal, index == 0 { continue }

            if placedCount > 0 {
                let deltaAngle = tightness / max(radius, minimumRadius)
                angle += deltaAngle
                radius = startRadius + angle * radiusGrowthPerRadian
            }

            let translation = CGPoint(
                x: cos(angle) * radius,
                y: sin(angle) * radius
            )
            let rotation = settings.rotateCopies ? angle : 0
            placements.append(Placement(translation: translation, rotation: rotation))
            placedCount += 1
        }
        return placements
    }

    private static func transformedCopy(
        _ stroke: VectorStroke,
        pivot: CGPoint,
        translation: CGPoint,
        rotation: CGFloat
    ) -> VectorStroke {
        var copy = stroke
        copy.id = UUID()

        if abs(rotation) > 0.000001 {
            copy = ShapeGeometry.rotatedStroke(copy, around: pivot, by: rotation)
        }

        copy.points = PrintLayoutCoordinateSpace.offsetPoints(copy.points, by: translation)
        if !copy.cutoutPoints.isEmpty {
            copy.cutoutPoints = copy.cutoutPoints.map {
                PrintLayoutCoordinateSpace.offsetPoints($0, by: translation)
            }
        }
        if let basePoints = copy.rotationBasePoints {
            copy.rotationBasePoints = PrintLayoutCoordinateSpace.offsetPoints(basePoints, by: translation)
        }
        if let baseCenter = copy.rotationBaseCenter {
            copy.rotationBaseCenter = CGPoint(
                x: baseCenter.x + translation.x,
                y: baseCenter.y + translation.y
            )
        }

        return ShapeGeometry.captureRotationBaseIfNeeded(copy)
    }

    private static func clamp(_ value: Int, min: Int, max: Int) -> Int {
        Swift.max(min, Swift.min(value, max))
    }
}
