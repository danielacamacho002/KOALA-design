//
//  SideToolPaletteView.swift
//  vectr
//

import SwiftUI

struct SideToolPaletteView: View {
    @Bindable var document: VectrDocument
    var onToolSelected: (ToolCategory?) -> Void

    private let iconSize: CGFloat = 34

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ToolCategory.shapeCategories, id: \.self) { category in
                toolButton(category)
            }

            ToolPaletteSeparator()

            ForEach(ToolCategory.actionCategories, id: \.self) { category in
                toolButton(category)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        }
    }

    @ViewBuilder
    private func toolButton(_ category: ToolCategory) -> some View {
        if category == .curve {
            StudioIconButton(
                isActive: isToolHighlighted(category),
                size: iconSize,
                inactiveColor: .white,
                action: { selectTool(category) }
            ) {
                CurveToolIcon()
                    .frame(width: 17, height: 17)
            }
            .accessibilityLabel(category.label)
        } else if category == .fillet {
            StudioIconButton(
                isActive: isToolHighlighted(category),
                size: iconSize,
                inactiveColor: .white,
                action: { selectTool(category) }
            ) {
                FilletToolIcon()
                    .frame(width: 17, height: 17)
            }
            .accessibilityLabel(category.label)
        } else {
            StudioIconButton(
                systemImage: category.systemImage,
                isActive: isToolHighlighted(category),
                size: iconSize,
                inactiveColor: .white,
                action: { selectTool(category) }
            )
            .accessibilityLabel(category.label)
        }
    }

    private func selectTool(_ category: ToolCategory) {
        if category == .move {
            document.engageMoveTool()
            onToolSelected(.move)
        } else if document.activeCategory == category {
            document.clearActiveTool()
            onToolSelected(.move)
        } else {
            document.selectTool(category)
            onToolSelected(category)
        }
    }

    /// Move stays visually idle as the default tool until the user taps it
    /// (or starts using it). Other tools highlight whenever they are active.
    private func isToolHighlighted(_ category: ToolCategory) -> Bool {
        guard document.activeCategory == category else { return false }
        if category == .move {
            return document.isMoveToolHighlighted
        }
        return true
    }
}

/// Scale tool options, presented as a left-aligned command panel matching the
/// other drawing tools (uniform vs. free scaling).
struct ScaleToolPanelView: View {
    @Bindable var document: VectrDocument
    var onVariantSelected: () -> Void

    private let options = ["Uniform", "Free"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToolPanelHeader("Scale")

            VStack(spacing: 2) {
                ForEach(Array(options.enumerated()), id: \.offset) { index, label in
                    ToolPanelLabelButton(
                        title: label,
                        prominent: index == selectedIndex,
                        fullWidth: true,
                        alignment: .leading
                    ) {
                        document.scaleUniform = index == 0
                        onVariantSelected()
                    }
                }
            }
        }
        .toolPanelChrome(width: ToolPanelMetrics.commandWidth)
    }

    private var selectedIndex: Int {
        document.scaleUniform ? 0 : 1
    }
}

/// A curve with an anchor at each end and one where the two bends meet.
struct CurveToolIcon: View {
    var body: some View {
        Canvas { context, size in
            let unit = min(size.width, size.height) / 17
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x * unit, y: y * unit)
            }

            let tangentY: CGFloat = 8.6
            let anchors = [pt(3.8, 14.0), pt(13.4, 3.2)]
            let squareSide = 3.05 * unit
            let squareCenter = pt(8.5, tangentY)

            var curve = Path()
            curve.move(to: anchors[0])
            curve.addCurve(to: pt(6.6, tangentY), control1: pt(5.0, 11.6), control2: pt(4.6, tangentY))
            curve.addLine(to: pt(10.4, tangentY))
            curve.addCurve(to: anchors[1], control1: pt(12.2, tangentY), control2: pt(12.2, 5.0))
            context.stroke(
                curve,
                with: .foreground,
                style: StrokeStyle(lineWidth: 1.4 * unit, lineCap: .round, lineJoin: .round)
            )

            let dotRadius = 1.65 * unit
            for anchor in anchors {
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: anchor.x - dotRadius,
                        y: anchor.y - dotRadius,
                        width: dotRadius * 2,
                        height: dotRadius * 2
                    )),
                    with: .foreground
                )
            }
            context.fill(
                Path(CGRect(
                    x: squareCenter.x - squareSide / 2,
                    y: squareCenter.y - squareSide / 2,
                    width: squareSide,
                    height: squareSide
                )),
                with: .foreground
            )
        }
        .accessibilityHidden(true)
    }
}

/// A square with one rounded corner and three sharp ones, so the fillet reads by contrast.
struct FilletToolIcon: View {
    var body: some View {
        Canvas { context, size in
            let unit = min(size.width, size.height) / 17
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x * unit, y: y * unit)
            }

            let lineWidth = 1.25 * unit
            let inset: CGFloat = 2.7
            let radius: CGFloat = 5.4
            let handle = radius * 0.5522847498
            let minX = inset
            let minY = inset
            let maxX = 17 - inset
            let maxY = 17 - inset

            var corner = Path()
            corner.move(to: pt(minX, minY + radius))
            corner.addLine(to: pt(minX, maxY))
            corner.addLine(to: pt(maxX, maxY))
            corner.addLine(to: pt(maxX, minY))
            corner.addLine(to: pt(minX + radius, minY))
            corner.addCurve(
                to: pt(minX, minY + radius),
                control1: pt(minX + radius - handle, minY),
                control2: pt(minX, minY + radius - handle)
            )
            corner.closeSubpath()
            context.stroke(
                corner,
                with: .foreground,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt, lineJoin: .miter)
            )
        }
        .accessibilityHidden(true)
    }
}

struct ToolPaletteSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 20)
            .padding(.horizontal, 4)
    }
}
