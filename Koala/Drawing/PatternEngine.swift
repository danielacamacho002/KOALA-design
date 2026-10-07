//
//  PatternEngine.swift
//  Koala
//

import CoreGraphics
import Foundation

enum PatternEngine {
    struct Placement {
        var translation: CGPoint
        var rotation: CGFloat
    }

    struct Application {
        /// When set, the source stroke is updated in place to the first pattern slot.
        var repositionedSource: VectorStroke?
        /// When true, the source stroke is removed after new strokes are added.
        var removeSource: Bool
        var newStrokes: [VectorStroke]
    }

    private static let minimumRadius: CGFloat = 1

    static func boundingSize(for stroke: VectorStroke) -> CGSize {
        let points = ShapeGeometry.renderPoints(for: stroke)
        let rect = PrintLayoutCoordinateSpace.boundingRect(for: points)
        guard !rect.isNull else { return .zero }
        return rect.size
    }

    static func generatedCopies(from stroke: VectorStroke, settings: PatternSettings) -> [VectorStroke] {
        let pivot = ShapeGeometry.shapeCenter(for: stroke)
            ?? strokeCenter(from: stroke)
        return computePlacements(from: stroke, settings: settings).map { placement in
            transformedCopy(
                stroke,
                pivot: pivot,
                translation: placement.translation,
                rotation: placement.rotation
            )
        }
    }

    static func application(
        from stroke: VectorStroke,
        sourceID: UUID,
        settings: PatternSettings
    ) -> Application {
        let pivot = ShapeGeometry.shapeCenter(for: stroke)
            ?? strokeCenter(from: stroke)
        let placements = computePlacements(from: stroke, settings: settings)

        guard !placements.isEmpty else {
            return Application(repositionedSource: nil, removeSource: false, newStrokes: [])
        }

        switch settings.mode {
        case .grid, .linear:
            let newStrokes = placements.map { placement in
                transformedCopy(
                    stroke,
                    pivot: pivot,
                    translation: placement.translation,
                    rotation: placement.rotation
                )
            }
            return Application(repositionedSource: nil, removeSource: true, newStrokes: newStrokes)

        case .radial, .spiral:
            if settings.keepOriginal {
                let newStrokes = placements.map { placement in
                    transformedCopy(
                        stroke,
                        pivot: pivot,
                        translation: placement.translation,
                        rotation: placement.rotation
                    )
                }
                return Application(repositionedSource: nil, removeSource: false, newStrokes: newStrokes)
            }

            var repositioned = transformedCopy(
                stroke,
                pivot: pivot,
                translation: placements[0].translation,
                rotation: placements[0].rotation
            )
            repositioned.id = sourceID

            let newStrokes = placements.dropFirst().map { placement in
                transformedCopy(
                    stroke,
                    pivot: pivot,
                    translation: placement.translation,
                    rotation: placement.rotation
                )
            }
            return Application(
                repositionedSource: repositioned,
                removeSource: false,
                newStrokes: newStrokes
            )
        }
    }

    private static func strokeCenter(from stroke: VectorStroke) -> CGPoint {
        let points = ShapeGeometry.renderPoints(for: stroke)
        return PrintLayoutCoordinateSpace.center(of: points)
    }

    private static func computePlacements(from stroke: VectorStroke, settings: PatternSettings) -> [Placement] {
        let shapeSize = boundingSize(for: stroke)
        switch settings.mode {
        case .grid:
            return gridPlacements(settings: settings, shapeSize: shapeSize)
        case .linear:
            return linearPlacements(settings: settings, shapeSize: shapeSize)
        case .radial:
            return radialPlacements(settings: settings)
        case .spiral:
            return spiralPlacements(settings: settings)
        }
    }

    /// Center-to-center step: shape size plus the edge gap. Gap 0 tiles copies so they touch.
    private static func step(shapeLength: CGFloat, gap: CGFloat) -> CGFloat {
        max(shapeLength, 0) + max(gap, 0)
    }

    private static func gridPlacements(settings: PatternSettings, shapeSize: CGSize) -> [Placement] {
        let rows = clamp(settings.rows, min: 1, max: PatternSettings.maxCount)
        let columns = clamp(settings.columns, min: 1, max: PatternSettings.maxCount)
        let total = min(rows * columns, PatternSettings.maxCount)
        let stepX = step(shapeLength: shapeSize.width, gap: settings.spacingX)
        let stepY = step(shapeLength: shapeSize.height, gap: settings.spacingY)
        var placements: [Placement] = []

        for index in 0..<total {
            let row = index / columns
            let column = index % columns
            placements.append(
                Placement(
                    translation: CGPoint(
                        x: CGFloat(column) * stepX,
                        y: CGFloat(row) * stepY
                    ),
                    rotation: 0
                )
            )
        }
        return placements
    }

    private static func linearPlacements(settings: PatternSettings, shapeSize: CGSize) -> [Placement] {
        let count = clamp(settings.count, min: 1, max: PatternSettings.maxCount)
        var placements: [Placement] = []

        for index in 0..<count {
            let offset: CGPoint
            switch settings.linearDirection {
            case .horizontal:
                let sign: CGFloat = settings.flipLinearDirection ? -1 : 1
                let stepX = step(shapeLength: shapeSize.width, gap: settings.spacingX)
                offset = CGPoint(x: CGFloat(index) * stepX * sign, y: 0)
            case .vertical:
                let stepY = step(shapeLength: shapeSize.height, gap: settings.spacingY)
                offset = CGPoint(x: 0, y: CGFloat(index) * stepY)
            }
            placements.append(Placement(translation: offset, rotation: 0))
        }
        return placements
    }

    private static func radialPlacements(settings: PatternSettings) -> [Placement] {
        let count = clamp(settings.count, min: 1, max: PatternSettings.maxCount)
        let startRadius = max(settings.startRadius, minimumRadius)
        let tightness = max(settings.tightness, minimumRadius)
        var placements: [Placement] = []

        for copyIndex in 0..<count {
            let angle: CGFloat
            if settings.radialSpreadEven {
                angle = CGFloat(copyIndex) * (2 * .pi / CGFloat(count))
            } else {
                angle = CGFloat(copyIndex) * (tightness / startRadius)
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
        let startRadius = max(settings.startRadius, minimumRadius)
        let tightness = max(settings.tightness, minimumRadius)
        let radiusGrowthPerRadian = tightness / (2 * .pi)
        var placements: [Placement] = []

        var angle: CGFloat = 0
        var radius = startRadius

        for copyIndex in 0..<count {
            if copyIndex > 0 {
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

        copy = copy.offsettingGeometry(by: translation)
        return ShapeGeometry.captureRotationBaseIfNeeded(copy)
    }

    private static func clamp(_ value: Int, min: Int, max: Int) -> Int {
        Swift.max(min, Swift.min(value, max))
    }
}
