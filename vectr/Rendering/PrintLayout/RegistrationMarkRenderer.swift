//
//  RegistrationMarkRenderer.swift
//  vectr
//

import CoreGraphics
import UIKit

enum RegistrationMarkRenderer {
    static let crosshairSize: CGFloat = 16

    static func makeMarkLayer(
        for mark: RegistrationMark,
        viewport: ViewportTransform,
        isInteractive: Bool
    ) -> CALayer {
        let container = CALayer()
        let center = viewport.documentToView(mark.position)
        container.position = center
        container.bounds = CGRect(x: 0, y: 0, width: 40, height: 40)
        container.anchorPoint = CGPoint(x: 0.5, y: 0.5)

        switch mark.kind {
        case .crosshair:
            let crosshair = makeCrosshairLayer(locked: mark.isLocked)
            crosshair.position = CGPoint(x: 20, y: 20)
            container.addSublayer(crosshair)
        case .pageNumber:
            let label = makeLabelLayer(text: mark.pageLabel ?? "?", locked: mark.isLocked)
            label.position = CGPoint(x: 20, y: 20)
            container.addSublayer(label)
        }

        if isInteractive, !mark.isLocked {
            container.opacity = 0.45
        }

        return container
    }

    static func hitTest(mark: RegistrationMark, at documentPoint: CGPoint, threshold: CGFloat) -> Bool {
        hypot(mark.position.x - documentPoint.x, mark.position.y - documentPoint.y) <= threshold
    }

    private static func makeCrosshairLayer(locked: Bool) -> CALayer {
        let layer = CAShapeLayer()
        let path = UIBezierPath()
        let half = crosshairSize / 2
        path.move(to: CGPoint(x: 20 - half, y: 20))
        path.addLine(to: CGPoint(x: 20 + half, y: 20))
        path.move(to: CGPoint(x: 20, y: 20 - half))
        path.addLine(to: CGPoint(x: 20, y: 20 + half))
        layer.path = path.cgPath
        layer.strokeColor = locked ? UIColor.label.cgColor : UIColor.secondaryLabel.cgColor
        layer.fillColor = UIColor.clear.cgColor
        layer.lineWidth = locked ? 1.5 : 1
        if !locked {
            layer.lineDashPattern = [4, 3]
        }
        layer.contentsScale = UIScreen.main.scale
        return layer
    }

    private static func makeLabelLayer(text: String, locked: Bool) -> CATextLayer {
        let layer = CATextLayer()
        layer.string = text
        layer.fontSize = 11
        layer.foregroundColor = locked ? UIColor.label.cgColor : UIColor.secondaryLabel.cgColor
        layer.alignmentMode = .center
        layer.contentsScale = UIScreen.main.scale
        layer.bounds = CGRect(x: 0, y: 0, width: 36, height: 16)
        return layer
    }

    static func drawMark(
        _ mark: RegistrationMark,
        in context: CGContext,
        viewport: ViewportTransform
    ) {
        guard mark.isLocked else { return }
        let center = viewport.documentToView(mark.position)
        context.saveGState()
        context.setStrokeColor(UIColor.black.cgColor)
        context.setLineWidth(1)
        switch mark.kind {
        case .crosshair:
            let half = viewport.documentToView(distance: crosshairSize / 2)
            context.move(to: CGPoint(x: center.x - half, y: center.y))
            context.addLine(to: CGPoint(x: center.x + half, y: center.y))
            context.move(to: CGPoint(x: center.x, y: center.y - half))
            context.addLine(to: CGPoint(x: center.x, y: center.y + half))
            context.strokePath()
        case .pageNumber:
            let text = mark.pageLabel ?? "?"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10),
                .foregroundColor: UIColor.black
            ]
            let size = (text as NSString).size(withAttributes: attributes)
            (text as NSString).draw(
                at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2),
                withAttributes: attributes
            )
        }
        context.restoreGState()
    }
}
