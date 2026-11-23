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

    /// The elements patterned as one unit: a single shape, or every member of a group.
    struct Source: Equatable {
        var strokes: [VectorStroke]
        var textElements: [TextElement] = []

        var isEmpty: Bool { strokes.isEmpty && textElements.isEmpty }
    }

    struct Application {
        /// When set, the source elements are updated in place (same IDs) to the first pattern slot.
        var repositionedSource: Source?
        /// When true, the source elements are removed after the copies are added.
        var removeSource: Bool
        /// One entry per placed copy; every element has a fresh ID.
        var copies: [Source]
    }

    private static let minimumRadius: CGFloat = 1

    static func boundingRect(for source: Source) -> CGRect {
        var rect = CGRect.null
        for stroke in source.strokes {
            rect = rect.union(PrintLayoutCoordinateSpace.boundingRect(for: ShapeGeometry.renderPoints(for: stroke)))
        }
        for text in source.textElements {
            rect = rect.union(text.boundingBox())
        }
        return rect
    }

    static func boundingSize(for source: Source) -> CGSize {
        let rect = boundingRect(for: source)
        guard !rect.isNull else { return .zero }
        return rect.size
    }

    /// Preview outlines for the copies. Text is shown as its rotated frame.
    static func previewStrokes(from source: Source, settings: PatternSettings) -> [VectorStroke] {
        let pivot = pivot(for: source)
        return computePlacements(from: source, settings: settings).flatMap { placement in
            let copy = transformedCopy(source, pivot: pivot, placement: placement, keepIDs: false)
            let textOutlines = copy.textElements.map { text in
                VectorStroke(
                    layerID: text.layerID,
                    points: text.corners(),
                    strokeWidth: 1,
                    isClosed: true
                )
            }
            return copy.strokes + textOutlines
        }
    }

    static func application(from source: Source, settings: PatternSettings) -> Application {
        let pivot = pivot(for: source)
        let placements = computePlacements(from: source, settings: settings)

        guard !source.isEmpty, !placements.isEmpty else {
            return Application(repositionedSource: nil, removeSource: false, copies: [])
        }

        func copies(_ slots: ArraySlice<Placement>) -> [Source] {
            slots.map { transformedCopy(source, pivot: pivot, placement: $0, keepIDs: false) }
        }

        switch settings.mode {
        case .grid, .linear:
            return Application(repositionedSource: nil, removeSource: true, copies: copies(placements[...]))

        case .radial, .spiral:
            if settings.keepOriginal {
                return Application(repositionedSource: nil, removeSource: false, copies: copies(placements[...]))
            }
            return Application(
                repositionedSource: transformedCopy(source, pivot: pivot, placement: placements[0], keepIDs: true),
                removeSource: false,
                copies: copies(placements.dropFirst())
            )
        }
    }

    /// A lone shape keeps its own center so circles/arcs rotate about their true center;
    /// a group rotates about its combined bounding-box center.
    private static func pivot(for source: Source) -> CGPoint {
        if source.strokes.count == 1, source.textElements.isEmpty,
           let center = ShapeGeometry.shapeCenter(for: source.strokes[0]) {
            return center
        }
        let rect = boundingRect(for: source)
        guard !rect.isNull else { return .zero }
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    private static func computePlacements(from source: Source, settings: PatternSettings) -> [Placement] {
        let shapeSize = boundingSize(for: source)
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
        _ source: Source,
        pivot: CGPoint,
        placement: Placement,
        keepIDs: Bool
    ) -> Source {
        let rotation = placement.rotation
        let translation = placement.translation
        let rotates = abs(rotation) > 0.000001

        let strokes = source.strokes.map { stroke -> VectorStroke in
            var copy = stroke
            if !keepIDs { copy.id = UUID() }
            if rotates {
                copy = ShapeGeometry.rotatedStroke(copy, around: pivot, by: rotation)
            }
            copy = copy.offsettingGeometry(by: translation)
            return ShapeGeometry.captureRotationBaseIfNeeded(copy)
        }

        let texts = source.textElements.map { text -> TextElement in
            var copy = text
            if !keepIDs { copy.id = UUID() }
            var center = copy.center
            if rotates {
                center = ShapeGeometry.rotatePoint(center, around: pivot, by: rotation)
                copy.rotation += rotation
            }
            let size = copy.textSize()
            copy.position = CGPoint(
                x: center.x - size.width / 2 + translation.x,
                y: center.y - size.height / 2 + translation.y
            )
            return copy
        }

        return Source(strokes: strokes, textElements: texts)
    }

    private static func clamp(_ value: Int, min: Int, max: Int) -> Int {
        Swift.max(min, Swift.min(value, max))
    }
}
