//
//  OnboardingDemoView.swift
//  Koala
//
//  Short looping sketches for a few design-tour steps. Drawn on a TimelineView
//  clock so they keep playing while step changes suppress SwiftUI animation.
//

import SwiftUI

/// Sketch shown inside the hover card for design-tour steps that have a demo.
enum OnboardingDemo: Equatable {
    case line
    case circle
    case rectangle
    case curve
    case text
    case edit
    case scale
    case dimensions
    case trim
    case fillet
    case addAnchor
    case pattern
    case copy
    case delete
    case constraints
    case snap(SnapConstraint)

    static func demo(for step: OnboardingStep) -> OnboardingDemo? {
        switch step.id {
        case "design.line": return .line
        case "design.circle": return .circle
        case "design.rectangle": return .rectangle
        case "design.curve": return .curve
        case "design.type": return .text
        case "design.move": return .edit
        case "design.scale": return .scale
        case "design.dimensions": return .dimensions
        case "design.trim": return .trim
        case "design.fillet": return .fillet
        case "design.addAnchor": return .addAnchor
        case "design.pattern": return .pattern
        case "design.copy": return .copy
        case "design.delete": return .delete
        case "design.snaps": return .constraints
        default:
            let prefix = "design.snap."
            guard step.id.hasPrefix(prefix) else { return nil }
            return SnapConstraint(rawValue: String(step.id.dropFirst(prefix.count))).map(OnboardingDemo.snap)
        }
    }
}

struct OnboardingDemoView: View {
    let demo: OnboardingDemo

    private let loopDuration: TimeInterval = 2.4
    @State private var started = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let phase = loopPhase(from: started, to: context.date)
            Canvas { canvas, size in
                draw(demo, in: canvas, size: size, phase: phase)
            }
        }
        .onChange(of: demo) { _, _ in
            started = Date()
        }
        .accessibilityHidden(true)
    }

    private func loopPhase(from start: Date, to date: Date) -> CGFloat {
        let elapsed = date.timeIntervalSince(start)
        let wrapped = elapsed.truncatingRemainder(dividingBy: loopDuration)
        let positive = wrapped < 0 ? wrapped + loopDuration : wrapped
        return CGFloat(positive / loopDuration)
    }

    private func draw(_ demo: OnboardingDemo, in canvas: GraphicsContext, size: CGSize, phase: CGFloat) {
        let opacity = loopOpacity(phase)
        switch demo {
        case .line:
            drawLine(in: canvas, size: size, phase: phase, opacity: opacity)
        case .circle:
            drawCircle(in: canvas, size: size, phase: phase, opacity: opacity)
        case .rectangle:
            drawRectangle(in: canvas, size: size, phase: phase, opacity: opacity)
        case .curve:
            drawCurve(in: canvas, size: size, phase: phase, opacity: opacity)
        case .text:
            drawText(in: canvas, size: size, phase: phase, opacity: opacity)
        case .edit:
            drawEdit(in: canvas, size: size, phase: phase, opacity: holdOpacity(phase, until: 0.96))
        case .scale:
            drawScale(in: canvas, size: size, phase: phase, opacity: opacity)
        case .dimensions:
            drawDimensions(in: canvas, size: size, phase: phase, opacity: opacity)
        case .trim:
            drawTrim(in: canvas, size: size, phase: phase, opacity: opacity)
        case .fillet:
            drawFillet(in: canvas, size: size, phase: phase, opacity: opacity)
        case .addAnchor:
            drawAddAnchor(in: canvas, size: size, phase: phase, opacity: opacity)
        case .pattern:
            drawPattern(in: canvas, size: size, phase: phase, opacity: holdOpacity(phase, until: 0.94))
        case .copy:
            drawCopy(in: canvas, size: size, phase: phase, opacity: opacity)
        case .delete:
            drawDelete(in: canvas, size: size, phase: phase, opacity: holdOpacity(phase, until: 0.94))
        case .constraints:
            drawConstraints(in: canvas, size: size, phase: phase, opacity: 1)
        case .snap(let kind):
            drawSnap(kind, in: canvas, size: size, phase: phase, opacity: 1)
        }
    }

    /// Full stroke through the hold, then a short fade so the loop can restart.
    private func loopOpacity(_ phase: CGFloat) -> Double {
        holdOpacity(phase, until: 0.9)
    }

    /// Keeps a sketch fully visible until `until`, then fades across the rest of the loop.
    private func holdOpacity(_ phase: CGFloat, until: CGFloat) -> Double {
        guard phase > until else { return 1 }
        return Double(1 - (phase - until) / (1 - until))
    }

    private func drawLine(in canvas: GraphicsContext, size: CGSize, phase: CGFloat, opacity: Double) {
        let inset: CGFloat = 16
        let start = CGPoint(x: inset, y: size.height - inset)
        let end = CGPoint(x: size.width - inset, y: inset)
        let drawn = segment(phase, from: 0.04, to: 0.68)
        let tip = lerp(start, end, drawn)
        strokeLine(from: start, to: tip, in: canvas, opacity: opacity)
        fillAnchor(at: start, in: canvas, opacity: opacity)
        if drawn < 0.995 {
            fillTouch(at: tip, in: canvas, opacity: opacity)
        } else {
            fillAnchor(at: end, in: canvas, opacity: opacity)
        }
    }

    private func drawCircle(in canvas: GraphicsContext, size: CGSize, phase: CGFloat, opacity: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let maxRadius = min(size.height / 2 - 18, 46)
        if phase < 0.46 {
            let drag = segment(phase, from: 0.04, to: 0.34)
            let radius = maxRadius * drag
            let angle = -CGFloat.pi / 5
            let rim = CGPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
            if radius > 1 {
                stroke(circlePath(center: center, radius: radius, amount: 1), in: canvas, opacity: opacity)
                strokeLine(from: center, to: rim, in: canvas, opacity: opacity * 0.45, lineWidth: 1)
            }
            fillAnchor(at: center, in: canvas, opacity: opacity)
            if radius > 1 {
                fillTouch(at: rim, in: canvas, opacity: opacity)
            }
        } else {
            let drag = segment(phase, from: 0.52, to: 0.82)
            let start = CGPoint(x: center.x - maxRadius, y: center.y)
            let end = lerp(start, CGPoint(x: center.x + maxRadius, y: center.y), drag)
            let radius = hypot(end.x - start.x, end.y - start.y) / 2
            let middle = lerp(start, end, 0.5)
            if radius > 1 {
                stroke(circlePath(center: middle, radius: radius, amount: 1), in: canvas, opacity: opacity)
                strokeLine(from: start, to: end, in: canvas, opacity: opacity * 0.45, lineWidth: 1)
            }
            fillAnchor(at: start, in: canvas, opacity: opacity)
            if radius > 1 {
                fillTouch(at: end, in: canvas, opacity: opacity)
            }
        }
    }

    private func drawRectangle(in canvas: GraphicsContext, size: CGSize, phase: CGFloat, opacity: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        if phase < 0.46 {
            let drag = segment(phase, from: 0.04, to: 0.34)
            let halfW: CGFloat = 50 * drag
            let halfH: CGFloat = 30 * drag
            let corner = CGPoint(x: center.x + halfW, y: center.y + halfH)
            if halfW > 1 {
                stroke(
                    Path(CGRect(x: center.x - halfW, y: center.y - halfH, width: halfW * 2, height: halfH * 2)),
                    in: canvas,
                    opacity: opacity
                )
                strokeLine(from: center, to: corner, in: canvas, opacity: opacity * 0.45, lineWidth: 1)
                fillTouch(at: corner, in: canvas, opacity: opacity)
            }
            fillAnchor(at: center, in: canvas, opacity: opacity)
        } else {
            let drag = segment(phase, from: 0.52, to: 0.82)
            let origin = CGPoint(x: center.x - 54, y: center.y - 26)
            let far = CGPoint(x: center.x + 54, y: center.y + 26)
            let corner = lerp(origin, far, drag)
            let drawn = CGRect(
                x: min(origin.x, corner.x),
                y: min(origin.y, corner.y),
                width: abs(corner.x - origin.x),
                height: abs(corner.y - origin.y)
            )
            if drawn.width > 1 {
                stroke(Path(drawn), in: canvas, opacity: opacity)
                fillTouch(at: corner, in: canvas, opacity: opacity)
            }
            fillAnchor(at: origin, in: canvas, opacity: opacity)
        }
    }

    private func drawText(in canvas: GraphicsContext, size: CGSize, phase: CGFloat, opacity: Double) {
        let reveal = segment(phase, from: 0.1, to: 0.58)
        let resolved = canvas.resolve(
            Text("Abc")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(.white)
        )
        let textSize = resolved.measure(in: size)
        let origin = CGPoint(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2
        )
        let baselineY = origin.y + textSize.height * 0.82
        strokeLine(
            from: CGPoint(x: origin.x - 8, y: baselineY),
            to: CGPoint(x: origin.x + textSize.width + 8, y: baselineY),
            in: canvas,
            opacity: opacity * 0.35,
            lineWidth: 1
        )
        canvas.drawLayer { layer in
            let shown = CGRect(x: origin.x, y: 0, width: max(textSize.width * reveal, 0.5), height: size.height)
            layer.clip(to: Path(shown))
            layer.opacity = opacity
            layer.draw(resolved, at: CGPoint(x: origin.x + textSize.width / 2, y: origin.y + textSize.height / 2))
        }
        let caretX = origin.x + textSize.width * reveal
        strokeLine(
            from: CGPoint(x: caretX, y: origin.y + 4),
            to: CGPoint(x: caretX, y: baselineY),
            in: canvas,
            opacity: opacity
        )
    }

    private func drawScale(in canvas: GraphicsContext, size: CGSize, phase: CGFloat, opacity: Double) {
        let small = CGSize(width: 36, height: 22)
        let large = CGSize(width: 92, height: 56)
        let grown = segment(phase, from: 0.14, to: 0.66)
        let current = CGSize(
            width: lerp(small.width, large.width, grown),
            height: lerp(small.height, large.height, grown)
        )
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        stroke(rect(small, at: CGPoint(x: center.x - small.width / 2, y: center.y - small.height / 2)), in: canvas, opacity: opacity * 0.28)
        stroke(rect(current, at: CGPoint(x: center.x - current.width / 2, y: center.y - current.height / 2)), in: canvas, opacity: opacity)
    }

    private func drawEdit(in canvas: GraphicsContext, size: CGSize, phase: CGFloat, opacity: Double) {
        let shape = CGSize(width: 72, height: 44)
        let middle = CGPoint(x: size.width / 2, y: size.height / 2)
        let start = CGPoint(x: size.width * 0.30, y: size.height / 2)
        let moved = segment(phase, from: 0.00, to: 0.22)
        let turned = segment(phase, from: 0.28, to: 0.48)
        let thickened = segment(phase, from: 0.54, to: 0.68)
        let place = lerp(start, middle, moved)
        let angle = turned * (-24 * CGFloat.pi / 180)
        stroke(
            rotatedRect(shape, center: place, angle: angle),
            in: canvas,
            opacity: opacity,
            lineWidth: lerp(1.5, 4.5, thickened)
        )
    }

    private func drawCurve(in canvas: GraphicsContext, size: CGSize, phase: CGFloat, opacity: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let start = CGPoint(x: center.x - 78, y: center.y + 26)
        let joint = CGPoint(x: center.x + 8, y: center.y + 26)
        let end = CGPoint(x: center.x + 56, y: center.y - 34)
        let first = segment(phase, from: 0.04, to: 0.30)
        let second = segment(phase, from: 0.36, to: 0.68)
        let handlesIn = segment(phase, from: 0.58, to: 0.78)
        let jointDrawn = lerp(start, joint, first)
        let endDrawn = lerp(joint, end, second)

        if second < 0.02 {
            strokeLine(from: start, to: jointDrawn, in: canvas, opacity: opacity)
            fillAnchor(at: start, in: canvas, opacity: opacity)
            fillTouch(at: jointDrawn, in: canvas, opacity: opacity)
            return
        }

        let anchors = [start, joint, endDrawn]
        strokePoints(
            ShapeGeometry.smoothCurvePoints(anchors: anchors, samplesPerSegment: 16),
            in: canvas,
            opacity: opacity
        )
        if handlesIn > 0.02 {
            let handles = ShapeGeometry.defaultCurveHandles(anchors: anchors)
            for (index, anchor) in anchors.enumerated() {
                drawCurveHandle(at: anchor, offset: handles[index].inOffset, in: canvas, opacity: opacity * Double(handlesIn))
                drawCurveHandle(at: anchor, offset: handles[index].outOffset, in: canvas, opacity: opacity * Double(handlesIn))
            }
        }
        fillAnchor(at: start, in: canvas, opacity: opacity)
        fillAnchor(at: joint, in: canvas, opacity: opacity)
        if second < 1 {
            fillTouch(at: endDrawn, in: canvas, opacity: opacity)
        } else {
            fillAnchor(at: end, in: canvas, opacity: opacity)
        }
    }

    private func drawCurveHandle(
        at anchor: CGPoint,
        offset: CGPoint,
        in canvas: GraphicsContext,
        opacity: Double
    ) {
        guard hypot(offset.x, offset.y) > 0.5 else { return }
        let tip = CGPoint(x: anchor.x + offset.x, y: anchor.y + offset.y)
        strokeLine(from: anchor, to: tip, in: canvas, opacity: opacity * 0.55, lineWidth: 1)
        fillDot(at: tip, radius: 2, in: canvas, opacity: opacity)
    }

    private func drawDimensions(in canvas: GraphicsContext, size: CGSize, phase: CGFloat, opacity: Double) {
        let shape = CGSize(width: 108, height: 56)
        let origin = CGPoint(
            x: size.width / 2 - shape.width / 2 - 16,
            y: (size.height - shape.height) / 2 + 10
        )
        stroke(rect(shape, at: origin), in: canvas, opacity: opacity)
        let anchor = CGPoint(x: origin.x + shape.width / 2, y: origin.y)
        let shown = segment(phase, from: 0.18, to: 0.55)
        guard shown > 0.01 else { return }

        let label = canvas.resolve(
            Text("24.00 in")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.accentColor)
        )
        let textSize = label.measure(in: size)
        let labelCenter = CGPoint(x: anchor.x + 34, y: anchor.y - 30)
        let leaderEnd = CGPoint(
            x: labelCenter.x - textSize.width / 2 - 3,
            y: labelCenter.y
        )
        let tip = lerp(anchor, leaderEnd, shown)
        strokeLine(
            from: anchor,
            to: tip,
            in: canvas,
            opacity: opacity * 0.55 * Double(shown),
            lineWidth: 1,
            color: Color.accentColor
        )
        fillTouch(at: anchor, in: canvas, opacity: opacity, color: Color.accentColor)
        canvas.drawLayer { layer in
            layer.opacity = opacity * Double(shown)
            layer.draw(label, at: labelCenter)
        }
    }

    private func drawTrim(in canvas: GraphicsContext, size: CGSize, phase: CGFloat, opacity: Double) {
        let shape = CGSize(width: 108, height: 64)
        let origin = CGPoint(
            x: (size.width - shape.width) / 2,
            y: (size.height - shape.height) / 2
        )
        let points = [
            origin,
            CGPoint(x: origin.x + shape.width, y: origin.y),
            CGPoint(x: origin.x + shape.width, y: origin.y + shape.height),
            CGPoint(x: origin.x, y: origin.y + shape.height),
        ]
        let edge = 1
        let tap = segment(phase, from: 0.10, to: 0.26)
        let marked = phase >= 0.40
        let removed = segment(phase, from: 0.56, to: 0.76)
        for index in points.indices {
            let next = (index + 1) % points.count
            let fade: CGFloat = index == edge ? 1 - removed : 1
            guard fade > 0.02 else { continue }
            strokeLine(
                from: points[index],
                to: points[next],
                in: canvas,
                opacity: opacity * Double(fade),
                color: index == edge && marked ? .red : .white
            )
        }
        fillCorners(of: CGRect(origin: origin, size: shape), in: canvas, opacity: opacity)
        if removed < 0.98 {
            let mid = lerp(points[edge], points[(edge + 1) % points.count], 0.5)
            fillTouch(
                at: mid,
                in: canvas,
                opacity: opacity * Double(tap) * Double(1 - removed)
            )
        }
    }

    private func drawFillet(in canvas: GraphicsContext, size: CGSize, phase: CGFloat, opacity: Double) {
        let shape = CGSize(width: 108, height: 64)
        let origin = CGPoint(
            x: (size.width - shape.width) / 2,
            y: (size.height - shape.height) / 2
        )
        let corner = CGPoint(x: origin.x + shape.width, y: origin.y)
        let appear = segment(phase, from: 0.08, to: 0.26)
        let drag = segment(phase, from: 0.34, to: 0.76)
        let radius = 22 * drag
        let into = CGPoint(x: -0.7071, y: 0.7071)
        let handle = CGPoint(
            x: corner.x + into.x * radius,
            y: corner.y + into.y * radius
        )

        if radius > 0.8 {
            stroke(filletedTopRight(shape, at: origin, radius: radius), in: canvas, opacity: opacity)
        } else {
            stroke(rect(shape, at: origin), in: canvas, opacity: opacity)
        }
        if appear > 0.02 {
            fillAnchor(at: corner, in: canvas, opacity: opacity * Double(max(appear, drag > 0 ? 1 : appear)))
        }
        if drag > 0.02 {
            fillTouch(at: handle, in: canvas, opacity: opacity)
        }
    }

    private func drawAddAnchor(in canvas: GraphicsContext, size: CGSize, phase: CGFloat, opacity: Double) {
        let shape = CGSize(width: 124, height: 64)
        let origin = CGPoint(
            x: (size.width - shape.width) / 2,
            y: (size.height - shape.height) / 2
        )
        let tap = segment(phase, from: 0.12, to: 0.28)
        let placed = segment(phase, from: 0.42, to: 0.58)
        stroke(rect(shape, at: origin), in: canvas, opacity: opacity)
        let corners = [
            origin,
            CGPoint(x: origin.x + shape.width, y: origin.y),
            CGPoint(x: origin.x + shape.width, y: origin.y + shape.height),
            CGPoint(x: origin.x, y: origin.y + shape.height),
        ]
        for corner in corners {
            fillAnchor(at: corner, in: canvas, opacity: opacity)
        }
        let midpoint = CGPoint(x: origin.x + shape.width / 2, y: origin.y)
        if placed > 0.02 {
            fillAnchor(at: midpoint, in: canvas, opacity: opacity * Double(placed))
        }
        if placed < 0.98 {
            fillTouch(
                at: midpoint,
                in: canvas,
                opacity: opacity * Double(tap) * Double(1 - placed)
            )
        }
    }

    private func drawPattern(in canvas: GraphicsContext, size: CGSize, phase: CGFloat, opacity: Double) {
        let shape = CGSize(width: 26, height: 18)
        let gap: CGFloat = 12
        let columns = 3
        let rows = 3
        let totalWidth = shape.width * CGFloat(columns) + gap * CGFloat(columns - 1)
        let totalHeight = shape.height * CGFloat(rows) + gap * CGFloat(rows - 1)
        let origin = CGPoint(
            x: (size.width - totalWidth) / 2,
            y: (size.height - totalHeight) / 2
        )
        let firstRow = [
            CGFloat(1),
            segment(phase, from: 0.06, to: 0.20),
            segment(phase, from: 0.22, to: 0.36),
        ]
        let laterRows = [
            segment(phase, from: 0.46, to: 0.60),
            segment(phase, from: 0.66, to: 0.80),
        ]
        for row in 0..<rows {
            for column in 0..<columns {
                let shown = row == 0 ? firstRow[column] : laterRows[row - 1]
                guard shown > 0.02 else { continue }
                let place = CGPoint(
                    x: origin.x + CGFloat(column) * (shape.width + gap),
                    y: origin.y + CGFloat(row) * (shape.height + gap)
                )
                stroke(rect(shape, at: place), in: canvas, opacity: opacity * Double(shown))
            }
        }
    }

    private func drawCopy(in canvas: GraphicsContext, size: CGSize, phase: CGFloat, opacity: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let appear = segment(phase, from: 0.22, to: 0.55)
        stroke(starPath(center: center, outer: 32, inner: 13), in: canvas, opacity: opacity)
        stroke(
            starPath(
                center: CGPoint(x: center.x + 40, y: center.y - 14),
                outer: 32,
                inner: 13
            ),
            in: canvas,
            opacity: opacity * Double(appear)
        )
    }

    private func drawDelete(in canvas: GraphicsContext, size: CGSize, phase: CGFloat, opacity: Double) {
        let shape = CGSize(width: 100, height: 64)
        let origin = CGPoint(
            x: (size.width - shape.width) / 2 - 8,
            y: (size.height - shape.height) / 2
        )
        let right = origin.x + shape.width
        let midY = origin.y + shape.height / 2
        let radius: CGFloat = 18
        let cutter = CGPoint(x: right, y: midY)
        let grow = segment(phase, from: 0.02, to: 0.28)
        let approach = segment(phase, from: 0.36, to: 0.50)
        let cut = segment(phase, from: 0.64, to: 0.80)
        let drawnRadius = radius * grow
        let angle = -CGFloat.pi / 5
        let rim = CGPoint(
            x: cutter.x + drawnRadius * cos(angle),
            y: cutter.y + drawnRadius * sin(angle)
        )
        let finalRim = CGPoint(
            x: cutter.x + radius * cos(angle),
            y: cutter.y + radius * sin(angle)
        )
        let inside = CGPoint(x: cutter.x + radius * 0.3, y: cutter.y - radius * 0.16)

        stroke(edgeNotchedRect(shape, at: origin, biteRadius: radius, cut: cut), in: canvas, opacity: opacity)
        if drawnRadius > 1 && cut < 0.995 {
            let circleOpacity = opacity * Double(1 - cut)
            stroke(circlePath(center: cutter, radius: drawnRadius, amount: 1), in: canvas, opacity: circleOpacity)
            strokeLine(
                from: cutter,
                to: rim,
                in: canvas,
                opacity: circleOpacity * 0.45 * Double(1 - approach),
                lineWidth: 1
            )
            fillAnchor(at: cutter, in: canvas, opacity: circleOpacity)
            let pencil = grow < 0.995 ? rim : lerp(finalRim, inside, approach)
            fillTouch(at: pencil, in: canvas, opacity: circleOpacity)
        }
    }

    private func drawSnap(
        _ kind: SnapConstraint,
        in canvas: GraphicsContext,
        size: CGSize,
        phase: CGFloat,
        opacity: Double
    ) {
        let lock = segment(phase, from: 0.16, to: 0.62)
        switch kind {
        case .endpoint:
            drawSquareSnap(in: canvas, size: size, lock: lock, opacity: opacity, marksTarget: false) { square in
                CGPoint(x: square.maxX, y: square.maxY)
            }

        case .midpoint:
            drawSquareSnap(in: canvas, size: size, lock: lock, opacity: opacity, marksTarget: true) { square in
                CGPoint(x: square.maxX, y: square.midY)
            }

        case .intersection:
            let side: CGFloat = 62
            let left = CGRect(
                x: size.width * 0.22,
                y: (size.height - side) / 2 - 14,
                width: side,
                height: side
            )
            let right = CGRect(
                x: left.maxX - 28,
                y: left.minY + 24,
                width: side,
                height: side
            )
            let crossing = CGPoint(x: left.maxX, y: right.minY)
            let start = CGPoint(x: min(size.width - 24, crossing.x + 96), y: max(16, crossing.y - 42))
            let end = snapTip(from: start, to: crossing, lock: lock)
            stroke(Path(left), in: canvas, opacity: opacity)
            stroke(Path(right), in: canvas, opacity: opacity)
            fillCorners(of: left, in: canvas, opacity: opacity)
            fillCorners(of: right, in: canvas, opacity: opacity)
            fillAnchor(at: crossing, in: canvas, opacity: opacity)
            strokeLine(from: start, to: end, in: canvas, opacity: opacity)
            fillMovingTip(at: end, progress: lock, in: canvas, opacity: opacity)

        case .center:
            let center = CGPoint(x: size.width * 0.38, y: size.height / 2)
            let start = CGPoint(x: size.width - 28, y: size.height * 0.74)
            let tip = snapTip(from: start, to: center, lock: lock)
            stroke(circlePath(center: center, radius: 36, amount: 1), in: canvas, opacity: opacity)
            fillAnchor(at: center, in: canvas, opacity: opacity)
            strokeLine(from: start, to: tip, in: canvas, opacity: opacity)
            fillMovingTip(at: tip, progress: lock, in: canvas, opacity: opacity)

        case .quadrant:
            let center = CGPoint(x: size.width * 0.4, y: size.height / 2)
            let radius: CGFloat = 36
            let right = CGPoint(x: center.x + radius, y: center.y)
            let start = CGPoint(x: size.width - 28, y: size.height * 0.72)
            let quadrants = [
                right,
                CGPoint(x: center.x, y: center.y - radius),
                CGPoint(x: center.x - radius, y: center.y),
                CGPoint(x: center.x, y: center.y + radius),
            ]
            stroke(circlePath(center: center, radius: radius, amount: 1), in: canvas, opacity: opacity)
            for point in quadrants {
                fillAnchor(at: point, in: canvas, opacity: opacity)
            }
            let tip = snapTip(from: start, to: right, lock: lock)
            strokeLine(from: start, to: tip, in: canvas, opacity: opacity)
            fillMovingTip(at: tip, progress: lock, in: canvas, opacity: opacity)

        case .tangent:
            let center = CGPoint(x: size.width * 0.36, y: size.height * 0.46)
            let radius: CGFloat = 32
            let touch = CGPoint(x: center.x, y: center.y - radius)
            let y = lerp(min(size.height - 16, center.y + radius + 22), touch.y, lock)
            let tip = CGPoint(x: center.x - 8, y: y)
            stroke(circlePath(center: center, radius: radius, amount: 1), in: canvas, opacity: opacity)
            strokeLine(
                from: tip,
                to: CGPoint(x: size.width - 28, y: y),
                in: canvas,
                opacity: opacity
            )
            fillMovingTip(at: tip, progress: lock, in: canvas, opacity: opacity)
            snapDot(at: touch, lock: lock, in: canvas, opacity: opacity)
        }
    }

    /// Square used by the endpoint and midpoint sketches, with a line locking onto `target`.
    private func drawSquareSnap(
        in canvas: GraphicsContext,
        size: CGSize,
        lock: CGFloat,
        opacity: Double,
        marksTarget: Bool,
        target: (CGRect) -> CGPoint
    ) {
        let side: CGFloat = 68
        let square = CGRect(
            x: size.width * 0.34 - side / 2,
            y: (size.height - side) / 2,
            width: side,
            height: side
        )
        let point = target(square)
        let start = CGPoint(x: size.width - 30, y: size.height - 20)
        let end = snapTip(from: start, to: point, lock: lock)
        stroke(Path(square), in: canvas, opacity: opacity)
        fillCorners(of: square, in: canvas, opacity: opacity)
        if marksTarget {
            fillAnchor(at: point, in: canvas, opacity: opacity)
        }
        strokeLine(from: start, to: end, in: canvas, opacity: opacity)
        fillMovingTip(at: end, progress: lock, in: canvas, opacity: opacity)
    }

    private func fillCorners(of rect: CGRect, in canvas: GraphicsContext, opacity: Double) {
        for point in [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY),
        ] {
            fillAnchor(at: point, in: canvas, opacity: opacity)
        }
    }

    /// Moving line tip. Begins well short of `target`, then closes onto it.
    private func snapTip(from start: CGPoint, to target: CGPoint, lock: CGFloat) -> CGPoint {
        let along = lerp(CGFloat(0.34), 1, lock)
        let straight = lerp(start, target, along)
        let dx = target.x - start.x
        let dy = target.y - start.y
        let length = max(hypot(dx, dy), 1)
        let side = 16 * (1 - lock)
        return CGPoint(
            x: straight.x + (-dy / length) * side,
            y: straight.y + (dx / length) * side
        )
    }
    private func fillMovingTip(
        at point: CGPoint,
        progress: CGFloat,
        in canvas: GraphicsContext,
        opacity: Double
    ) {
        guard progress > 0.02, progress < 0.98 else { return }
        fillTouch(at: point, in: canvas, opacity: opacity)
    }

    private func snapDot(at point: CGPoint, lock: CGFloat, in canvas: GraphicsContext, opacity: Double) {
        fillDot(
            at: point,
            radius: 2.2 + 1.6 * lock,
            in: canvas,
            opacity: opacity * (0.4 + 0.6 * Double(lock))
        )
    }

    private func drawConstraints(in canvas: GraphicsContext, size: CGSize, phase: CGFloat, opacity: Double) {
        let meet = CGPoint(x: size.width / 2, y: size.height / 2)
        let approach = segment(phase, from: 0.12, to: 0.62)
        let travel = lerp(CGFloat(72), 0, approach)
        let reach: CGFloat = 58
        let half: CGFloat = 30
        let fixed = [
            meet,
            CGPoint(x: meet.x - reach, y: meet.y - half),
            CGPoint(x: meet.x - reach, y: meet.y + half),
        ]
        let movingTip = CGPoint(x: meet.x + travel, y: meet.y)
        let moving = [
            movingTip,
            CGPoint(x: movingTip.x + reach, y: meet.y - half),
            CGPoint(x: movingTip.x + reach, y: meet.y + half),
        ]
        stroke(triangle(fixed), in: canvas, opacity: opacity)
        stroke(triangle(moving), in: canvas, opacity: opacity)
        for point in fixed + moving {
            fillAnchor(at: point, in: canvas, opacity: opacity)
        }
        let center = CGPoint(
            x: (moving[0].x + moving[1].x + moving[2].x) / 3,
            y: (moving[0].y + moving[1].y + moving[2].y) / 3
        )
        if approach > 0.02 && approach < 0.98 {
            fillTouch(at: center, in: canvas, opacity: opacity)
        }
    }

    private func triangle(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }

    private func strokeLine(
        from start: CGPoint,
        to end: CGPoint,
        in canvas: GraphicsContext,
        opacity: Double,
        lineWidth: CGFloat = 1.5,
        color: Color = .white
    ) {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        stroke(path, in: canvas, opacity: opacity, lineWidth: lineWidth, color: color)
    }

    private func stroke(
        _ path: Path,
        in canvas: GraphicsContext,
        opacity: Double,
        lineWidth: CGFloat = 1.5,
        color: Color = .white
    ) {
        canvas.stroke(
            path,
            with: .color(color.opacity(opacity)),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt, lineJoin: .miter)
        )
    }

    private func fillDot(
        at center: CGPoint,
        radius: CGFloat,
        in canvas: GraphicsContext,
        opacity: Double,
        color: Color = .white
    ) {
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        canvas.fill(Path(ellipseIn: rect), with: .color(color.opacity(opacity)))
    }

    /// Placed anchor. A solid square, separate from the pencil mark.
    private func fillAnchor(
        at center: CGPoint,
        in canvas: GraphicsContext,
        opacity: Double,
        side: CGFloat = 5
    ) {
        guard side > 0.4 else { return }
        let rect = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
        canvas.fill(Path(rect), with: .color(Color.white.opacity(opacity)))
    }

    /// Apple Pencil mark. A light circle, separate from the anchor squares.
    private func fillTouch(
        at center: CGPoint,
        in canvas: GraphicsContext,
        opacity: Double,
        color: Color = .white
    ) {
        fillDot(at: center, radius: 3.4, in: canvas, opacity: opacity * 0.4, color: color)
    }

    private func rotatedRect(_ size: CGSize, center: CGPoint, angle: CGFloat) -> Path {
        let corners = [
            CGPoint(x: -size.width / 2, y: -size.height / 2),
            CGPoint(x: size.width / 2, y: -size.height / 2),
            CGPoint(x: size.width / 2, y: size.height / 2),
            CGPoint(x: -size.width / 2, y: size.height / 2),
        ]
        let placed = corners.map { corner in
            CGPoint(
                x: center.x + corner.x * cos(angle) - corner.y * sin(angle),
                y: center.y + corner.x * sin(angle) + corner.y * cos(angle)
            )
        }
        var path = Path()
        path.move(to: placed[0])
        for corner in placed.dropFirst() {
            path.addLine(to: corner)
        }
        path.closeSubpath()
        return path
    }

    private func strokePoints(_ points: [CGPoint], in canvas: GraphicsContext, opacity: Double) {
        guard let first = points.first, points.count >= 2 else { return }
        var path = Path()
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        stroke(path, in: canvas, opacity: opacity)
    }

    private func circlePath(center: CGPoint, radius: CGFloat, amount: CGFloat) -> Path {
        guard amount > 0.001 else { return Path() }
        if amount > 0.995 {
            return Path(ellipseIn: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
        }
        var arc = Path()
        arc.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * amount),
            clockwise: false
        )
        return arc
    }

    /// Quarter turn around the top-right corner, from the top edge to the right edge.
    private func filletedTopRight(_ size: CGSize, at origin: CGPoint, radius: CGFloat) -> Path {
        let right = origin.x + size.width
        let bottom = origin.y + size.height
        let center = CGPoint(x: right - radius, y: origin.y + radius)
        var path = Path()
        path.move(to: CGPoint(x: origin.x, y: origin.y))
        path.addLine(to: CGPoint(x: right - radius, y: origin.y))
        let steps = 12
        for step in 1...steps {
            let angle = (CGFloat(step) / CGFloat(steps)) * (.pi / 2)
            path.addLine(to: CGPoint(
                x: center.x + radius * sin(angle),
                y: center.y - radius * cos(angle)
            ))
        }
        path.addLine(to: CGPoint(x: right, y: bottom))
        path.addLine(to: CGPoint(x: origin.x, y: bottom))
        path.closeSubpath()
        return path
    }

    private func starPath(center: CGPoint, outer: CGFloat, inner: CGFloat) -> Path {
        var path = Path()
        for index in 0..<10 {
            let angle = CGFloat(index) * .pi / 5 - .pi / 2
            let radius = index.isMultiple(of: 2) ? outer : inner
            let point = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }

    private func rect(_ size: CGSize, at origin: CGPoint) -> Path {
        Path(CGRect(origin: origin, size: size))
    }

    /// Rectangle whose right edge opens into a semicircular bite. `cut` of 0 is the full edge.
    private func edgeNotchedRect(_ size: CGSize, at origin: CGPoint, biteRadius: CGFloat, cut: CGFloat) -> Path {
        let right = origin.x + size.width
        let bottom = origin.y + size.height
        let midY = origin.y + size.height / 2
        let topBite = midY - biteRadius
        var path = Path()
        path.move(to: CGPoint(x: origin.x, y: origin.y))
        path.addLine(to: CGPoint(x: right, y: origin.y))
        path.addLine(to: CGPoint(x: right, y: topBite))
        let steps = 16
        for step in 1..<steps {
            let s = CGFloat(step) / CGFloat(steps)
            let angle = -.pi / 2 - s * .pi
            let straight = CGPoint(x: right, y: topBite + s * biteRadius * 2)
            let arc = CGPoint(
                x: right + cos(angle) * biteRadius,
                y: midY + sin(angle) * biteRadius
            )
            path.addLine(to: lerp(straight, arc, cut))
        }
        path.addLine(to: CGPoint(x: right, y: midY + biteRadius))
        path.addLine(to: CGPoint(x: right, y: bottom))
        path.addLine(to: CGPoint(x: origin.x, y: bottom))
        path.closeSubpath()
        return path
    }

    private func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }

    /// 0 before `from`, 1 after `to`, smoothstep in between.
    private func segment(_ phase: CGFloat, from: CGFloat, to: CGFloat) -> CGFloat {
        let t = min(max((phase - from) / (to - from), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
