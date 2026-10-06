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
/// other drawing tools (uniform vs. free scaling, plus a numeric factor).
struct ScaleToolPanelView: View {
    @Bindable var document: VectrDocument
    var onChanged: () -> Void

    private enum Axis {
        case uniform, width, height
    }

    /// Step for the plus / minus buttons, as a multiple of current size.
    private static let factorStep = 0.1
    private static let minimumFactor = 0.01
    private static let maximumFactor = 100.0

    private let options = ["Uniform", "Free"]

    /// Factors already applied since the selection became current. `1` is the size on screen.
    @State private var lastUniform = 1.0
    @State private var lastWidth = 1.0
    @State private var lastHeight = 1.0
    @State private var uniformText = "1"
    @State private var widthText = "1"
    @State private var heightText = "1"
    @State private var editing: Axis?
    /// Geometry revision produced by this panel, so handle drags and undo reset the fields
    /// without wiping a factor the panel itself just committed.
    @State private var appliedGeometryRevision = -1

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                ToolPanelHeader("Scale")

                ToolPanelSegmentBar(
                    options: options,
                    selectedIndex: selectedIndex
                ) { index in
                    document.scaleUniform = index == 0
                    onChanged()
                }
                // Chrome pads the panel by 8; pull the bar out so it sits 2pt from both edges.
                .padding(.horizontal, -6)
            }

            Divider()

            if document.scaleUniform {
                factorStepper(
                    label: "Scale",
                    text: $uniformText,
                    axis: .uniform
                )
            } else {
                factorStepper(
                    label: "Width",
                    text: $widthText,
                    axis: .width
                )
                factorStepper(
                    label: "Height",
                    text: $heightText,
                    axis: .height
                )
            }
        }
        .toolPanelChrome(width: ToolPanelMetrics.commandWidth)
        .onChange(of: document.geometryRevision) { _, revision in
            guard revision != appliedGeometryRevision else { return }
            resetBaselines()
        }
        .onChange(of: document.selectedStrokeIDs) { _, _ in resetBaselines() }
        .onChange(of: document.selectedTextIDs) { _, _ in resetBaselines() }
        .onChange(of: document.selectedReferenceImageID) { _, _ in resetBaselines() }
        .onChange(of: document.scaleUniform) { _, isUniform in
            guard isUniform else { return }
            if abs(lastWidth - lastHeight) > 0.0001 {
                lastUniform = 1
            } else {
                lastUniform = lastWidth
            }
            syncFields()
        }
    }

    private var selectedIndex: Int {
        document.scaleUniform ? 0 : 1
    }

    private func factorStepper(label: String, text: Binding<String>, axis: Axis) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ToolPanelSectionLabel(label)

            ToolPanelNumericStepper(
                text: text,
                placeholder: "1",
                unitLabel: "×",
                keyboardType: .decimalPad,
                onMinus: { step(axis, by: -Self.factorStep) },
                onPlus: { step(axis, by: Self.factorStep) },
                onSubmit: { commitText(axis) },
                onEditingChanged: { isEditing in
                    editing = isEditing ? axis : (editing == axis ? nil : editing)
                }
            )
        }
    }

    private func step(_ axis: Axis, by delta: Double) {
        let next = stepped(baseline(for: axis) + delta)
        apply(factor: next, axis: axis)
    }

    private func commitText(_ axis: Axis) {
        guard let value = parsedFactor(text(for: axis)) else {
            syncFields()
            return
        }
        apply(factor: min(Self.maximumFactor, max(Self.minimumFactor, value)), axis: axis)
    }

    /// `factor` is the cumulative multiple shown in the field (1 = size when the selection was made).
    private func apply(factor: Double, axis: Axis) {
        let baseline = baseline(for: axis)
        guard baseline > 0 else {
            syncFields()
            return
        }
        let relative = factor / baseline
        let fx: CGFloat
        let fy: CGFloat
        switch axis {
        case .uniform:
            fx = CGFloat(relative)
            fy = CGFloat(relative)
        case .width:
            fx = CGFloat(relative)
            fy = 1
        case .height:
            fx = 1
            fy = CGFloat(relative)
        }

        guard document.hasCanvasSelection else {
            syncFields()
            return
        }

        let didScale = document.scaleSelectedElements(factorX: fx, factorY: fy)
        appliedGeometryRevision = document.geometryRevision
        guard didScale else {
            syncFields()
            return
        }

        switch axis {
        case .uniform:
            lastUniform = factor
            lastWidth = factor
            lastHeight = factor
        case .width:
            lastWidth = factor
            if abs(lastWidth - lastHeight) <= 0.0001 {
                lastUniform = factor
            }
        case .height:
            lastHeight = factor
            if abs(lastWidth - lastHeight) <= 0.0001 {
                lastUniform = factor
            }
        }
        syncFields()
        onChanged()
    }

    private func baseline(for axis: Axis) -> Double {
        switch axis {
        case .uniform: lastUniform
        case .width: lastWidth
        case .height: lastHeight
        }
    }

    private func text(for axis: Axis) -> String {
        switch axis {
        case .uniform: uniformText
        case .width: widthText
        case .height: heightText
        }
    }

    private func resetBaselines() {
        lastUniform = 1
        lastWidth = 1
        lastHeight = 1
        editing = nil
        uniformText = "1"
        widthText = "1"
        heightText = "1"
    }

    private func syncFields() {
        if editing != .uniform { uniformText = factorString(lastUniform) }
        if editing != .width { widthText = factorString(lastWidth) }
        if editing != .height { heightText = factorString(lastHeight) }
    }

    private func stepped(_ value: Double) -> Double {
        let snapped = (value * 10).rounded() / 10
        return min(Self.maximumFactor, max(Self.minimumFactor, snapped))
    }

    private func parsedFactor(_ raw: String) -> Double? {
        let cleaned = raw
            .replacingOccurrences(of: "×", with: "")
            .replacingOccurrences(of: "x", with: "")
            .replacingOccurrences(of: "X", with: "")
            .replacingOccurrences(of: "*", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Double(cleaned), value > 0, value.isFinite else { return nil }
        return value
    }

    private func factorString(_ value: Double) -> String {
        var text = String(format: "%.3f", value)
        while text.contains(".") && (text.hasSuffix("0") || text.hasSuffix(".")) {
            text.removeLast()
        }
        return text.isEmpty ? "0" : text
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
