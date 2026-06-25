//
//  PrintLayoutOverlayView.swift
//  vectr
//

import SwiftUI

struct PrintLayoutOverlayView: View {
    @Bindable var document: VectrDocument
    var onChanged: () -> Void

    @State private var moveDragOriginTransform = PrintStrokeTransform.identity
    @State private var rotateDragOriginAngle: CGFloat = 0
    @State private var rotateDragOriginRotation: CGFloat = 0

    private let handleSize: CGFloat = 22
    private let rotateHandleOffset: CGFloat = 36
    private let coordinateSpaceName = "printLayout"

    var body: some View {
        GeometryReader { _ in
            ZStack {
                if document.printLayout.activeTool == .select,
                   let strokeID = document.printSelectedStrokeID,
                   let stroke = document.stroke(with: strokeID) {
                    selectionOverlay(strokeID: strokeID, stroke: stroke)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .coordinateSpace(name: coordinateSpaceName)
    }

    @ViewBuilder
    private func selectionOverlay(strokeID: UUID, stroke: VectorStroke) -> some View {
        let transformed = document.transformedPrintStroke(stroke)
        let points = ShapeGeometry.renderPoints(for: transformed)
        let bbox = PrintLayoutCoordinateSpace.boundingRect(for: points)
        let center = CGPoint(x: bbox.midX, y: bbox.midY)
        let viewCenter = document.viewport.documentToView(center)

        // Bounding box
        RoundedRectangle(cornerRadius: 2)
            .stroke(Color.accentColor.opacity(0.5), lineWidth: 1)
            .frame(
                width: document.viewport.documentToView(distance: bbox.width),
                height: document.viewport.documentToView(distance: bbox.height)
            )
            .position(document.viewport.documentToView(CGPoint(x: bbox.midX, y: bbox.midY)))
            .allowsHitTesting(false)

        // Move handle (center)
        Circle()
            .fill(Color.accentColor)
            .frame(width: centerHandleSize, height: centerHandleSize)
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .position(viewCenter)
            .gesture(moveDrag(strokeID: strokeID))

        // Rotation handle
        Image(systemName: "arrow.triangle.2.circlepath")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: handleSize, height: handleSize)
            .background(Circle().fill(Color.orange))
            .position(
                x: viewCenter.x,
                y: viewCenter.y - document.viewport.documentToView(distance: rotateHandleOffset)
            )
            .gesture(rotateDrag(strokeID: strokeID, center: center))
    }

    private var centerHandleSize: CGFloat { 18 }

    private func moveDrag(strokeID: UUID) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                if moveDragOriginTransform == .identity {
                    moveDragOriginTransform = document.printTransform(for: strokeID)
                    document.beginInteractiveEdit()
                }
                let startDoc = document.viewport.viewToDocument(value.startLocation)
                let currentDoc = document.viewport.viewToDocument(value.location)
                let delta = CGPoint(
                    x: currentDoc.x - startDoc.x,
                    y: currentDoc.y - startDoc.y
                )
                var transform = moveDragOriginTransform
                transform.translation = CGPoint(
                    x: moveDragOriginTransform.translation.x + delta.x,
                    y: moveDragOriginTransform.translation.y + delta.y
                )
                document.setPrintTransform(transform, for: strokeID, recordUndo: false)
                onChanged()
            }
            .onEnded { _ in
                moveDragOriginTransform = .identity
            }
    }

    private func rotateDrag(strokeID: UUID, center: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                let currentDoc = document.viewport.viewToDocument(value.location)
                if rotateDragOriginRotation == 0, rotateDragOriginAngle == 0 {
                    rotateDragOriginRotation = document.printTransform(for: strokeID).rotation
                    rotateDragOriginAngle = atan2(currentDoc.y - center.y, currentDoc.x - center.x)
                    document.beginInteractiveEdit()
                }
                let angle = atan2(currentDoc.y - center.y, currentDoc.x - center.x)
                var transform = document.printTransform(for: strokeID)
                transform.rotation = rotateDragOriginRotation + (angle - rotateDragOriginAngle)
                document.setPrintTransform(transform, for: strokeID, recordUndo: false)
                onChanged()
            }
            .onEnded { _ in
                rotateDragOriginAngle = 0
                rotateDragOriginRotation = 0
            }
    }
}
