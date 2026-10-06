//
//  SnapGlyphIcons.swift
//  Koala
//

import SwiftUI

private enum SnapGlyphMetrics {
    static let side: CGFloat = 17
    /// Matches SF Symbol regular weight at 17pt.
    static let lineWidth: CGFloat = 1.1
    static let dotRadius: CGFloat = 1.75
    /// Keeps the circle glyphs the same outer size as the 17pt neighbors.
    static let circleInset: CGFloat = 2.45
}

/// Open square-corner (an L) with a filled dot on the vertex and another on the
/// free end of one arm — the two places an endpoint snap can lock.
struct EndpointSnapIcon: View {
    var body: some View {
        Canvas { context, size in
            let inset = size.width * 0.18
            let corner = CGPoint(x: size.width - inset, y: inset)
            let bottom = CGPoint(x: size.width - inset, y: size.height - inset)
            let left = CGPoint(x: inset, y: inset)
            let lineWidth = SnapGlyphMetrics.lineWidth
            let dotRadius = SnapGlyphMetrics.dotRadius

            var cornerPath = Path()
            cornerPath.move(to: bottom)
            cornerPath.addLine(to: corner)
            cornerPath.addLine(to: left)

            context.stroke(
                cornerPath,
                with: .foreground,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )
            context.fill(dot(at: corner, radius: dotRadius), with: .foreground)
            context.fill(dot(at: left, radius: dotRadius), with: .foreground)
        }
        .accessibilityHidden(true)
    }
}

/// A straight segment with a filled dot at its midpoint.
struct MidpointSnapIcon: View {
    var body: some View {
        Canvas { context, size in
            let inset = size.width * 0.06
            let start = CGPoint(x: inset, y: size.height / 2)
            let end = CGPoint(x: size.width - inset, y: size.height / 2)
            let mid = CGPoint(x: size.width / 2, y: size.height / 2)
            let lineWidth = SnapGlyphMetrics.lineWidth
            let dotRadius = SnapGlyphMetrics.dotRadius

            var line = Path()
            line.move(to: start)
            line.addLine(to: end)

            context.stroke(
                line,
                with: .foreground,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            context.fill(dot(at: mid, radius: dotRadius), with: .foreground)
        }
        .accessibilityHidden(true)
    }
}

/// Circle with filled dots at the four cardinal apexes (0° / 90° / 180° / 270°).
/// Drawn in a slightly larger canvas so the ring can match the 17pt neighbors
/// while the cardinal dots still fit on the path.
struct QuadrantSnapIcon: View {
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let lineWidth = SnapGlyphMetrics.lineWidth
            let dotRadius = SnapGlyphMetrics.dotRadius
            let radius = min(size.width, size.height) / 2 - SnapGlyphMetrics.circleInset

            let circle = Path(ellipseIn: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            context.stroke(
                circle,
                with: .foreground,
                style: StrokeStyle(lineWidth: lineWidth)
            )

            let cardinals = [
                CGPoint(x: center.x, y: center.y - radius),
                CGPoint(x: center.x + radius, y: center.y),
                CGPoint(x: center.x, y: center.y + radius),
                CGPoint(x: center.x - radius, y: center.y)
            ]
            for point in cardinals {
                context.fill(dot(at: point, radius: dotRadius), with: .foreground)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Circle with a straight line kissing the rim — tangent, not a secant through the middle.
struct TangentSnapIcon: View {
    var body: some View {
        Canvas { context, size in
            let lineWidth = SnapGlyphMetrics.lineWidth
            let inset = SnapGlyphMetrics.circleInset
            let radius = min(size.width, size.height) / 2 - inset
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let stroke = StrokeStyle(lineWidth: lineWidth, lineCap: .round)

            let circle = Path(ellipseIn: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            context.stroke(circle, with: .foreground, style: stroke)

            let tangentY = center.y - radius
            var tangent = Path()
            tangent.move(to: CGPoint(x: inset * 0.35, y: tangentY))
            tangent.addLine(to: CGPoint(x: size.width - inset * 0.35, y: tangentY))
            context.stroke(tangent, with: .foreground, style: stroke)
        }
        .accessibilityHidden(true)
    }
}

private func dot(at center: CGPoint, radius: CGFloat) -> Path {
    Path(ellipseIn: CGRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
    ))
}
