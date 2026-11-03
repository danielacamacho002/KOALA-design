import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import Koala

@MainActor
struct CanvasRenderSpaceTests {
    @Test func theWidestSheetFitsInTheLayerCoordinateLimit() {
        let compressed = CanvasRenderSpace.compress(CanvasRenderSpace.maxDocumentSpan)
        #expect(abs(compressed - CanvasRenderSpace.safeSpan) < 0.001)
    }

    @Test func aFloorPlanRectangleStaysInsideTheSafeSpan() {
        let width = UnitConversion.documentPoints(from: 324, unit: .inches)
        let height = UnitConversion.documentPoints(from: 157, unit: .inches)
        let corners = ShapeGeometry.rectangleFromCorners(
            CGPoint(x: -width / 2, y: -height / 2),
            CGPoint(x: width / 2, y: height / 2)
        )
        let local = corners.map(CanvasRenderSpace.compress)
        let spanX = (local.map(\.x).max() ?? 0) - (local.map(\.x).min() ?? 0)
        let spanY = (local.map(\.y).max() ?? 0) - (local.map(\.y).min() ?? 0)

        #expect(spanX <= CanvasRenderSpace.safeSpan)
        #expect(spanY <= CanvasRenderSpace.safeSpan)
        #expect(spanX > CanvasRenderSpace.safeSpan * 0.2)
    }

    @Test func compressedPointsRoundTripThroughTheLayerTransform() {
        var viewport = ViewportTransform()
        viewport.scale = 0.05
        viewport.translation = CGPoint(x: 400, y: 300)
        let documentPoint = CGPoint(
            x: -UnitConversion.documentPoints(from: 162, unit: .inches),
            y: UnitConversion.documentPoints(from: 70, unit: .inches)
        )

        let mapped = CanvasRenderSpace.compress(documentPoint)
            .applying(CanvasRenderSpace.layerTransform(for: viewport))
        let expected = viewport.documentToView(documentPoint)

        #expect(abs(mapped.x - expected.x) < 0.01)
        #expect(abs(mapped.y - expected.y) < 0.01)
    }

    @Test func theOriginCompressesToTheOrigin() {
        #expect(CanvasRenderSpace.compress(CGPoint.zero) == .zero)
        #expect(CanvasRenderSpace.compress(CGFloat(0)) == 0)
    }

    @Test func aLargeRectanglePathMatchesTheViewportAfterTheLayerTransform() {
        let width = UnitConversion.documentPoints(from: 324, unit: .inches)
        let height = UnitConversion.documentPoints(from: 157, unit: .inches)
        let stroke = VectorStroke(
            layerID: UUID(),
            points: ShapeGeometry.rectangleFromCorners(
                CGPoint(x: -width / 2, y: -height / 2),
                CGPoint(x: width / 2, y: height / 2)
            ),
            strokeWidth: 2,
            isClosed: true,
            shapeType: .rectangle
        )
        var viewport = ViewportTransform()
        viewport.scale = 0.04
        viewport.translation = CGPoint(x: 500, y: 400)

        let viewPath = StrokeRenderer.path(for: stroke, viewport: viewport).cgPath
        let localPath = StrokeRenderer.path(for: stroke, viewport: CanvasRenderSpace.pathViewport).cgPath
        var transform = CanvasRenderSpace.layerTransform(for: viewport)
        let mapped = localPath.copy(using: &transform) ?? localPath
        let localBounds = localPath.boundingBoxOfPath

        #expect(localBounds.width <= CanvasRenderSpace.safeSpan)
        #expect(localBounds.height <= CanvasRenderSpace.safeSpan)

        let viewElements = pathElements(viewPath)
        let mappedElements = pathElements(mapped)
        #expect(viewElements.count == mappedElements.count)
        for (viewElement, mappedElement) in zip(viewElements, mappedElements) {
            #expect(viewElement.type == mappedElement.type)
            for (viewPoint, mappedPoint) in zip(viewElement.points, mappedElement.points) {
                #expect(abs(viewPoint.x - mappedPoint.x) < 0.05)
                #expect(abs(viewPoint.y - mappedPoint.y) < 0.05)
            }
        }
    }

    private func pathElements(_ path: CGPath) -> [(type: CGPathElementType, points: [CGPoint])] {
        var elements: [(type: CGPathElementType, points: [CGPoint])] = []
        path.applyWithBlock { element in
            let points = element.pointee.points
            let stored: [CGPoint]
            switch element.pointee.type {
            case .moveToPoint, .addLineToPoint:
                stored = [points[0]]
            case .addQuadCurveToPoint:
                stored = [points[0], points[1]]
            case .addCurveToPoint:
                stored = [points[0], points[1], points[2]]
            case .closeSubpath:
                stored = []
            @unknown default:
                stored = []
            }
            elements.append((element.pointee.type, stored))
        }
        return elements
    }
}
