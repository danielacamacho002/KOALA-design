//
//  SnapFeedback.swift
//  vectr
//
//  Visual + haptic feedback for the snapping engine. Kept separate from the engine math so
//  feedback can be restyled or muted without touching snap resolution.
//

import QuartzCore
import UIKit

// MARK: - Haptics

/// Fires a crisp native impact exactly when the cursor locks onto a snap point.
///
/// `prepare()` should be called when a snap-capable gesture begins so the Taptic Engine is
/// warm and the pulse lands with sub-frame latency at the moment of lock.
final class SnapHaptics {
    private let generator = UIImpactFeedbackGenerator(style: .rigid)

    /// Warm up the Taptic Engine ahead of an imminent lock to minimize latency.
    func prepare() {
        generator.prepare()
    }

    /// Play the lock pulse. Re-primes the generator for the next lock.
    func play() {
        generator.impactOccurred(intensity: 0.9)
        generator.prepare()
    }
}

// MARK: - Visual indicator

/// Draws the high-contrast snap marker under the cursor: a small square for endpoints and
/// a small triangle for midpoints. Owns a single `CAShapeLayer` that is repositioned each
/// frame and hidden when there is no active lock.
final class SnapIndicatorRenderer {
    /// Marker glyph size (view points).
    private let markerSize: CGFloat = 13
    /// Sits above stroke previews (`DrawingCanvasUIView.previewZPosition == 10_000`).
    private let indicatorZPosition: CGFloat = 20_000

    private var indicatorLayer: CAShapeLayer?

    /// Position the marker at `viewPoint` for the given snap `kind`, or hide it when `nil`.
    func update(kind: SnapKind?, viewPoint: CGPoint?, in hostLayer: CALayer) {
        guard let kind, let viewPoint else {
            indicatorLayer?.isHidden = true
            return
        }

        let markerLayer = ensureLayer(in: hostLayer)
        markerLayer.isHidden = false

        // No implicit position/path animation — the marker must track the pencil crisply.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // The concentric "center" glyph needs even-odd fill to punch its ring; every other
        // glyph is a solid fill. Reset it each frame since the layer is shared across kinds.
        markerLayer.fillRule = (kind == .center) ? .evenOdd : .nonZero
        switch kind {
        case .endpoint:
            markerLayer.path = squarePath(center: viewPoint, size: markerSize)
        case .midpoint:
            markerLayer.path = trianglePath(center: viewPoint, size: markerSize)
        case .intersection:
            markerLayer.path = crossPath(center: viewPoint, size: markerSize)
        case .center:
            markerLayer.path = concentricPath(center: viewPoint, size: markerSize)
        case .quadrant:
            markerLayer.path = diamondPath(center: viewPoint, size: markerSize)
        case .tangent:
            markerLayer.path = tangentPath(center: viewPoint, size: markerSize)
        }
        CATransaction.commit()
    }

    /// Hide the indicator (call when a gesture ends).
    func clear() {
        indicatorLayer?.isHidden = true
    }

    private func ensureLayer(in hostLayer: CALayer) -> CAShapeLayer {
        if let indicatorLayer, indicatorLayer.superlayer === hostLayer {
            return indicatorLayer
        }
        indicatorLayer?.removeFromSuperlayer()

        let created = CAShapeLayer()
        created.zPosition = indicatorZPosition
        // High-contrast fill with a white halo so the marker reads on light and dark canvases.
        created.fillColor = UIColor.systemPink.withAlphaComponent(0.95).cgColor
        created.strokeColor = UIColor.white.cgColor
        created.lineWidth = 1.5
        created.lineJoin = .round
        created.contentsScale = UIScreen.main.scale
        hostLayer.addSublayer(created)
        indicatorLayer = created
        return created
    }

    private func squarePath(center: CGPoint, size: CGFloat) -> CGPath {
        let half = size / 2
        return UIBezierPath(
            rect: CGRect(x: center.x - half, y: center.y - half, width: size, height: size)
        ).cgPath
    }

    private func trianglePath(center: CGPoint, size: CGFloat) -> CGPath {
        // Upward-pointing equilateral-ish triangle centered on the point.
        let half = size / 2
        let path = UIBezierPath()
        path.move(to: CGPoint(x: center.x, y: center.y - half))
        path.addLine(to: CGPoint(x: center.x + half, y: center.y + half))
        path.addLine(to: CGPoint(x: center.x - half, y: center.y + half))
        path.close()
        return path.cgPath
    }

    /// Concentric-circle glyph (⊙): an outer ring plus a center dot, drawn with even-odd fill.
    private func concentricPath(center: CGPoint, size: CGFloat) -> CGPath {
        let outer = size / 2
        let path = UIBezierPath(ovalIn: CGRect(
            x: center.x - outer, y: center.y - outer, width: size, height: size
        ))
        let mid = outer * 0.55
        path.append(UIBezierPath(ovalIn: CGRect(
            x: center.x - mid, y: center.y - mid, width: mid * 2, height: mid * 2
        )))
        let dot = outer * 0.24
        path.append(UIBezierPath(ovalIn: CGRect(
            x: center.x - dot, y: center.y - dot, width: dot * 2, height: dot * 2
        )))
        return path.cgPath
    }

    /// Diamond glyph (⋄) for quadrant apexes.
    private func diamondPath(center: CGPoint, size: CGFloat) -> CGPath {
        let half = size / 2
        let path = UIBezierPath()
        path.move(to: CGPoint(x: center.x, y: center.y - half))
        path.addLine(to: CGPoint(x: center.x + half, y: center.y))
        path.addLine(to: CGPoint(x: center.x, y: center.y + half))
        path.addLine(to: CGPoint(x: center.x - half, y: center.y))
        path.close()
        return path.cgPath
    }

    /// Tangent glyph: a small disc with a line kissing its top edge.
    private func tangentPath(center: CGPoint, size: CGFloat) -> CGPath {
        let discRadius = size * 0.36
        let discCenterY = center.y + size * 0.12
        let path = UIBezierPath(ovalIn: CGRect(
            x: center.x - discRadius,
            y: discCenterY - discRadius,
            width: discRadius * 2,
            height: discRadius * 2
        ))
        let barHeight: CGFloat = 2.4
        let barWidth = size
        let barY = discCenterY - discRadius - barHeight / 2
        path.append(UIBezierPath(rect: CGRect(
            x: center.x - barWidth / 2, y: barY, width: barWidth, height: barHeight
        )))
        return path.cgPath
    }

    private func crossPath(center: CGPoint, size: CGFloat) -> CGPath {
        let path = UIBezierPath()
        for (index, vertex) in SnapMarkerGeometry.crossVertices(size: size).enumerated() {
            let placed = CGPoint(x: center.x + vertex.x, y: center.y + vertex.y)
            if index == 0 { path.move(to: placed) } else { path.addLine(to: placed) }
        }
        path.close()
        return path.cgPath
    }
}

/// Shared vertex math for the intersection "X" marker so the UIKit indicator and the SwiftUI
/// move-tool overlay render an identical glyph.
enum SnapMarkerGeometry {
    /// A solid X (a plus rotated 45°) centered on the origin, sized to `size`.
    static func crossVertices(size: CGFloat) -> [CGPoint] {
        let h = size / 2
        let t = size * 0.17
        let base: [CGPoint] = [
            CGPoint(x: -t, y: -h), CGPoint(x: t, y: -h), CGPoint(x: t, y: -t),
            CGPoint(x: h, y: -t), CGPoint(x: h, y: t), CGPoint(x: t, y: t),
            CGPoint(x: t, y: h), CGPoint(x: -t, y: h), CGPoint(x: -t, y: t),
            CGPoint(x: -h, y: t), CGPoint(x: -h, y: -t), CGPoint(x: -t, y: -t)
        ]
        let angle = CGFloat.pi / 4
        let c = cos(angle)
        let s = sin(angle)
        return base.map { CGPoint(x: $0.x * c - $0.y * s, y: $0.x * s + $0.y * c) }
    }
}
