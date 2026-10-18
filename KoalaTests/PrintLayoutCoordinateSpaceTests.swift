import CoreGraphics
import Foundation
import Testing
@testable import Koala

@MainActor
struct PrintLayoutCoordinateSpaceTests {
    @Test func emptyPointsHaveNullBounds() {
        #expect(PrintLayoutCoordinateSpace.boundingRect(for: []) == .null)
    }

    @Test func identityTransformLeavesPointsUnchanged() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 4)]
        let result = PrintLayoutCoordinateSpace.transformedPoints(points, transform: .identity)
        #expect(result == points)
    }

    @Test func translationOffsetsAllPoints() {
        let points = [CGPoint(x: 1, y: 2), CGPoint(x: 3, y: 4)]
        let transform = PrintStrokeTransform(translation: CGPoint(x: 5, y: -3))
        let result = PrintLayoutCoordinateSpace.transformedPoints(points, transform: transform)
        #expect(result == [CGPoint(x: 6, y: -1), CGPoint(x: 8, y: 1)])
    }

    @Test func rotatingACurveKeepsItsBend() {
        let stroke = VectorStroke(
            layerID: UUID(),
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)],
            isClosed: false,
            shapeType: .curve,
            curveHandles: [
                CurveHandle(outOffset: CGPoint(x: 0, y: -80)),
                CurveHandle(inOffset: CGPoint(x: 0, y: -80))
            ]
        )
        let before = ShapeGeometry.renderPoints(for: stroke)
        let pivot = PrintLayoutCoordinateSpace.center(of: before)
        let transform = PrintStrokeTransform(
            translation: CGPoint(x: 15, y: -4),
            rotation: .pi / 2
        )

        let after = ShapeGeometry.renderPoints(
            for: PrintLayoutCoordinateSpace.transformedStroke(stroke, transform: transform)
        )

        #expect(before.count == after.count)
        #expect(before.count > 2)
        for (original, rotated) in zip(before, after) {
            expectNear(
                rotated,
                translate(rotate(original, around: pivot, by: .pi / 2), by: transform.translation)
            )
        }
    }

    @Test func rotatingMovesAnOffsetHoleWithTheOutline() {
        let stroke = VectorStroke(
            layerID: UUID(),
            points: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 100, y: 0),
                CGPoint(x: 100, y: 100),
                CGPoint(x: 0, y: 100)
            ],
            isClosed: true,
            shapeType: .rectangle,
            cutoutPoints: [[
                CGPoint(x: 10, y: 10),
                CGPoint(x: 20, y: 10),
                CGPoint(x: 20, y: 20),
                CGPoint(x: 10, y: 20)
            ]]
        )
        let pivot = PrintLayoutCoordinateSpace.center(of: ShapeGeometry.renderPoints(for: stroke))
        let transformed = PrintLayoutCoordinateSpace.transformedStroke(
            stroke,
            transform: PrintStrokeTransform(rotation: .pi)
        )

        let hole = transformed.cutoutPoints[0]
        #expect(hole.count == 4)
        expectNear(hole[0], rotate(CGPoint(x: 10, y: 10), around: pivot, by: .pi))
        expectNear(hole[2], rotate(CGPoint(x: 20, y: 20), around: pivot, by: .pi))
    }

    @Test func rotatingAnArcKeepsItsSweep() {
        let stroke = VectorStroke(
            layerID: UUID(),
            points: [
                CGPoint(x: 40, y: 0),
                CGPoint(x: 0, y: 40),
                CGPoint(x: -40, y: 0)
            ],
            isClosed: false,
            shapeType: .arc
        )
        let before = ShapeGeometry.renderPoints(for: stroke)
        let pivot = PrintLayoutCoordinateSpace.center(of: before)
        let angle: CGFloat = 1.2
        let after = ShapeGeometry.renderPoints(
            for: PrintLayoutCoordinateSpace.transformedStroke(
                stroke,
                transform: PrintStrokeTransform(rotation: angle)
            )
        )

        #expect(before.count == after.count)
        #expect(before.count > 8)
        for (original, rotated) in zip(before, after) {
            expectNear(rotated, rotate(original, around: pivot, by: angle))
        }
    }

    @Test func rotatingAnEllipseKeepsItsAxes() {
        let stroke = VectorStroke(
            layerID: UUID(),
            points: ShapeGeometry.ellipseCardinalPoints(
                center: CGPoint(x: 10, y: 20),
                rx: 40,
                ry: 10
            ),
            isClosed: true,
            shapeType: .ellipse,
            shapeRotation: .pi / 6
        )
        let before = ShapeGeometry.renderPoints(for: stroke)
        let pivot = PrintLayoutCoordinateSpace.center(of: before)
        let angle: CGFloat = 0.4
        let after = ShapeGeometry.renderPoints(
            for: PrintLayoutCoordinateSpace.transformedStroke(
                stroke,
                transform: PrintStrokeTransform(rotation: angle)
            )
        )

        #expect(before.count == after.count)
        for (original, rotated) in zip(before, after) {
            expectNear(rotated, rotate(original, around: pivot, by: angle))
        }
    }

    private func rotate(_ point: CGPoint, around pivot: CGPoint, by angle: CGFloat) -> CGPoint {
        let cosR = cos(angle)
        let sinR = sin(angle)
        let dx = point.x - pivot.x
        let dy = point.y - pivot.y
        return CGPoint(
            x: pivot.x + dx * cosR - dy * sinR,
            y: pivot.y + dx * sinR + dy * cosR
        )
    }

    private func translate(_ point: CGPoint, by offset: CGPoint) -> CGPoint {
        CGPoint(x: point.x + offset.x, y: point.y + offset.y)
    }

    private func expectNear(_ actual: CGPoint, _ expected: CGPoint) {
        #expect(abs(actual.x - expected.x) < 0.02)
        #expect(abs(actual.y - expected.y) < 0.02)
    }
}
