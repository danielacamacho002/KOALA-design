//
//  MoveRotatePanelView.swift
//  vectr
//

import SwiftUI

struct MoveRotatePanelView: View {
    @Bindable var document: VectrDocument
    var units: MeasurementUnit
    var onApply: () -> Void

    /// Thickness step in document points so behavior is consistent across measurement units.
    private static let thicknessStepPoints: CGFloat = 0.5
    /// Fill opacity step as a fraction of fully opaque (5 percentage points).
    private static let fillOpacityStep: CGFloat = 0.05

    /// Font size / stroke weight stepping for the selected text.
    private static let fontSizeStep: CGFloat = 1
    private static let fontSizeRange: ClosedRange<CGFloat> = 6...200
    private static let textStrokeStep: CGFloat = 0.5
    private static let textStrokeRange: ClosedRange<CGFloat> = 0.5...48

    @State private var degreesText = ""
    @State private var isEditingDegrees = false
    @State private var thicknessText = ""
    @State private var fillOpacityText = ""
    @State private var imageOpacityText = ""
    @State private var isEditingImageOpacity = false
    @State private var showTextFillPicker = false
    @State private var showTextStrokePicker = false
    @State private var showColorPicker = false
    @State private var showFillColorPicker = false

    private var selectedStroke: VectorStroke? {
        guard let id = document.selectedStrokeID else { return nil }
        return document.stroke(with: id)
    }

    private var isTextSelected: Bool {
        document.selectedStrokeID == nil && document.selectedTextID != nil
    }

    /// An imported image is selected on its own, so stroke and text controls stay hidden.
    private var isImageSelected: Bool {
        document.isReferenceImageSelected && document.selectionIsEmpty
    }

    private var selectedText: TextElement? {
        guard let id = document.selectedTextID else { return nil }
        return document.textElement(with: id)
    }

    private var currentDegrees: Double {
        if isImageSelected {
            return ShapeGeometry.normalizedRotationDegrees(document.selectedReferenceImage?.rotation ?? 0)
        }
        if isTextSelected {
            return ShapeGeometry.normalizedRotationDegrees(selectedText?.rotation ?? 0)
        }
        return selectedStroke?.rotationDegrees ?? 0
    }

    /// Angle shown in the rotate stepper. One object uses its absolute rotation.
    /// A multi-selection uses the degrees applied since it was selected.
    private var displayedRotationDegrees: Double {
        if document.hasMultiSelection {
            return document.groupHandleRotationDegrees ?? 0
        }
        return currentDegrees
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToolPanelLabelButton(
                title: document.moveAxisLockEnabled ? "Axis locked" : "Lock to XY axis",
                prominent: document.moveAxisLockEnabled,
                fullWidth: true
            ) {
                document.moveAxisLockEnabled.toggle()
            }

            Divider()

            rotateSection

            if isImageSelected {
                Divider()
                imageOpacitySection
            }

            if !document.selectedTextIDs.isEmpty {
                Divider()
                textStyleSection
            }

            if !document.selectedStrokeIDs.isEmpty {
                Divider()
                thicknessSection

                Divider()
                colorSection
            }

            if document.hasClosedFillableSelection {
                Divider()
                fillColorSection

                Divider()
                fillOpacitySection
            }

            if document.usesGroupTransform {
                Divider()
                multiSelectionSection
            }

            Divider()

            if isImageSelected {
                ToolPanelLabelButton(title: "Delete", fullWidth: true) {
                    document.deleteSelectedElements()
                    onApply()
                }
            } else {
                arrangeSection
            }
        }
        .toolPanelChrome(width: ToolPanelMetrics.commandWidth)
        .onChange(of: document.selectedStrokeID) { _, _ in
            syncDegreesField()
            syncThicknessText()
            syncFillOpacity()
        }
        .onChange(of: document.selectedStrokeIDs) { _, _ in
            syncDegreesField()
            syncThicknessText()
            syncFillOpacity()
        }
        .onChange(of: document.selectedTextID) { _, _ in
            syncDegreesField()
        }
        .onChange(of: document.selectedTextIDs) { _, _ in
            syncDegreesField()
        }
        .onChange(of: document.selectedReferenceImageID) { _, _ in
            syncDegreesField()
            syncImageOpacity()
        }
        .onChange(of: document.geometryRevision) { _, _ in
            syncDegreesField()
            syncThicknessTextIfNeeded()
            syncImageOpacity()
        }
        .onAppear {
            syncDegreesField()
            syncThicknessText()
            syncFillOpacity()
            syncImageOpacity()
        }
    }

    // MARK: - Text style

    /// Number of text elements in the current selection.
    private var selectedTextCount: Int {
        document.selectedTextIDs.count
    }

    @ViewBuilder
    private var textStyleSection: some View {
        ToolPanelHeader(selectedTextCount > 1 ? "Text (\(selectedTextCount))" : "Text")

        Toggle(isOn: textOutlineBinding) {
            Text("Outline")
                .font(.system(size: 12))
        }
        .toggleStyle(.switch)

        textColorRow(
            label: "Fill",
            swatch: currentTextFillColor,
            accessibility: "Fill color"
        ) { showTextFillPicker = true }
        .sheet(isPresented: $showTextFillPicker) {
            TextStyleColorPickerSheet(color: textFillColorBinding)
        }

        textColorRow(
            label: "Stroke",
            swatch: currentTextStrokeColor,
            accessibility: "Stroke color"
        ) { showTextStrokePicker = true }
        .sheet(isPresented: $showTextStrokePicker) {
            TextStyleColorPickerSheet(color: textStrokeColorBinding)
        }

        textStepperRow(
            label: "Size",
            value: "\(Int(currentTextFontSize))",
            onMinus: { stepTextFontSize(by: -Self.fontSizeStep) },
            onPlus: { stepTextFontSize(by: Self.fontSizeStep) }
        )

        textStepperRow(
            label: "Stroke weight",
            value: textStrokeWidthLabel,
            onMinus: { stepTextStrokeWidth(by: -Self.textStrokeStep) },
            onPlus: { stepTextStrokeWidth(by: Self.textStrokeStep) }
        )
    }

    private func textColorRow(
        label: String,
        swatch: Color,
        accessibility: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            ToolPanelSectionLabel(label)
                .frame(width: 44, alignment: .leading)

            Rectangle()
                .fill(swatch)
                .frame(width: 24, height: 24)
                .overlay(Rectangle().stroke(Color.primary.opacity(0.15), lineWidth: 1))

            Button(action: action) {
                textColorWheel
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibility)

            Spacer()
        }
    }

    private func textStepperRow(
        label: String,
        value: String,
        onMinus: @escaping () -> Void,
        onPlus: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ToolPanelSectionLabel(label)

            HStack(spacing: 6) {
                ToolPanelIconButton(systemImage: "minus", action: onMinus)

                Text(value)
                    .font(.caption.monospacedDigit())
                    .frame(maxWidth: .infinity)
                    .frame(height: 26)
                    .background(Color.toolPanelButtonFill)

                ToolPanelIconButton(systemImage: "plus", action: onPlus)
            }
        }
    }

    private var textColorWheel: some View {
        Circle()
            .fill(
                AngularGradient(
                    colors: (0...12).map { Color(hue: Double($0) / 12.0, saturation: 0.85, brightness: 0.95) },
                    center: .center
                )
            )
            .overlay(
                Circle().fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.85), Color.white.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 13
                    )
                )
            )
    }

    /// Representative text element whose values populate the style controls.
    /// With multiple texts selected this is the first one in document order.
    private var representativeText: TextElement? {
        document.representativeSelectedText
    }

    private var currentTextFillColor: Color {
        (representativeText?.color ?? CodableColor(.primary)).color
    }

    private var currentTextStrokeColor: Color {
        (representativeText?.strokeColor ?? CodableColor(.primary)).color
    }

    private var currentTextFontSize: CGFloat {
        representativeText?.fontSize ?? document.activeFontSize
    }

    private var currentTextStrokeWidth: CGFloat {
        representativeText?.strokeWidth ?? TextElement.defaultStrokeWidth
    }

    private var textStrokeWidthLabel: String {
        let width = currentTextStrokeWidth
        if width.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f pt", width)
        }
        return String(format: "%.1f pt", width)
    }

    private var textOutlineBinding: Binding<Bool> {
        Binding(
            get: { representativeText?.isOutline ?? false },
            set: { newValue in
                document.setSelectedTextsOutline(newValue, recordUndo: true)
                onApply()
            }
        )
    }

    private var textFillColorBinding: Binding<Color> {
        Binding(
            get: { currentTextFillColor },
            set: { newValue in
                document.setSelectedTextsFillColor(CodableColor(newValue))
                onApply()
            }
        )
    }

    private var textStrokeColorBinding: Binding<Color> {
        Binding(
            get: { currentTextStrokeColor },
            set: { newValue in
                document.setSelectedTextsStrokeColor(CodableColor(newValue))
                onApply()
            }
        )
    }

    private func stepTextFontSize(by delta: CGFloat) {
        guard !document.selectedTextIDs.isEmpty else { return }
        let clamped = min(Self.fontSizeRange.upperBound, max(Self.fontSizeRange.lowerBound, currentTextFontSize + delta))
        document.activeFontSize = clamped
        document.setSelectedTextsFontSize(clamped, recordUndo: true)
        onApply()
    }

    private func stepTextStrokeWidth(by delta: CGFloat) {
        guard !document.selectedTextIDs.isEmpty else { return }
        let clamped = min(Self.textStrokeRange.upperBound, max(Self.textStrokeRange.lowerBound, currentTextStrokeWidth + delta))
        document.setSelectedTextsStrokeWidth(clamped, recordUndo: true)
        onApply()
    }

    @ViewBuilder
    private var thicknessSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            ToolPanelSectionLabel("Thickness")

            ToolPanelNumericStepper(
                text: $thicknessText,
                placeholder: "0",
                unitLabel: units.shortLabel,
                onMinus: { stepThickness(by: -Self.thicknessStepPoints) },
                onPlus: { stepThickness(by: Self.thicknessStepPoints) },
                onSubmit: applyThickness
            )
        }
    }

    @ViewBuilder
    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            ToolPanelSectionLabel("Color")

            HStack(spacing: 2) {
                Rectangle()
                    .fill(currentStrokeColor)
                    .frame(width: 26, height: 26)
                    .overlay(Rectangle().stroke(Color.primary.opacity(0.15), lineWidth: 1))

                Button {
                    showColorPicker = true
                } label: {
                    Image(systemName: "eyedropper")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.blue)
                        .frame(width: 24, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Line and border color")
                .sheet(isPresented: $showColorPicker) {
                    SystemColorPickerSheet(
                        color: strokeColorBinding,
                        onBeginEditing: { document.beginInteractiveEdit() }
                    )
                }

                if isStrokeColorMixed {
                    Text("Mixed")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var currentStrokeColor: Color {
        (document.representativeSelectedStrokeColor() ?? document.strokeColor).color
    }

    private var isStrokeColorMixed: Bool {
        document.selectedStrokeColorSummary() == .mixed
    }

    /// Programmatic-free binding: writes flow to the selected strokes without recording undo
    /// per change (a single snapshot is taken via `onBeginEditing`).
    private var strokeColorBinding: Binding<Color> {
        Binding(
            get: { currentStrokeColor },
            set: { newColor in
                document.setSelectedStrokesColor(CodableColor(newColor), recordUndo: false)
                onApply()
            }
        )
    }

    @ViewBuilder
    private var fillColorSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            ToolPanelSectionLabel("Fill")

            HStack(spacing: 2) {
                Rectangle()
                    .fill(currentFillColor)
                    .frame(width: 26, height: 26)
                    .overlay(Rectangle().stroke(Color.primary.opacity(0.15), lineWidth: 1))

                Button {
                    showFillColorPicker = true
                } label: {
                    Image(systemName: "eyedropper")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.blue)
                        .frame(width: 24, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Fill color")
                .sheet(isPresented: $showFillColorPicker) {
                    SystemColorPickerSheet(
                        color: fillColorBinding,
                        onBeginEditing: { document.beginInteractiveEdit() }
                    )
                }

                if isFillColorMixed {
                    Text("Mixed")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var currentFillColor: Color {
        if let color = document.representativeSelectedFillColor() {
            return color.color
        }
        return Color(uiColor: .systemGray)
    }

    private var isFillColorMixed: Bool {
        document.selectedFillColorSummary() == .mixed
    }

    /// Writes the picked color onto selected closed shapes. One undo snapshot is taken
    /// when the picker opens (`onBeginEditing`); later samples do not record again.
    private var fillColorBinding: Binding<Color> {
        Binding(
            get: { currentFillColor },
            set: { newColor in
                document.setSelectedStrokesFillColor(CodableColor(newColor), recordUndo: false)
                onApply()
            }
        )
    }

    @ViewBuilder
    private var fillOpacitySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            ToolPanelSectionLabel("Fill opacity")

            ToolPanelNumericStepper(
                text: $fillOpacityText,
                placeholder: "0",
                unitLabel: "%",
                onMinus: { stepFillOpacity(by: -Self.fillOpacityStep) },
                onPlus: { stepFillOpacity(by: Self.fillOpacityStep) },
                onSubmit: applyFillOpacity
            )
        }
    }

    @ViewBuilder
    private var rotateSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            ToolPanelSectionLabel("Rotate")

            ToolPanelNumericStepper(
                text: $degreesText,
                placeholder: "0",
                unitLabel: "°",
                keyboardType: .numbersAndPunctuation,
                onMinus: { stepRotation(by: -1) },
                onPlus: { stepRotation(by: 1) },
                onSubmit: apply,
                onEditingChanged: { isEditingDegrees = $0 }
            )

            ToolPanelLabelButton(
                title: "Rotate",
                prominent: document.isMoveRotateMode,
                fullWidth: true
            ) {
                document.isMoveRotateMode.toggle()
            }
        }
    }

    @ViewBuilder
    private var multiSelectionSection: some View {
        ToolPanelHeader("\(document.selectionCount) selected")

        HStack(spacing: 4) {
            ToolPanelLabelButton(
                title: "Group",
                isDisabled: !document.canGroupSelection,
                fullWidth: true
            ) {
                document.groupSelectedElements()
                onApply()
            }

            ToolPanelLabelButton(
                title: "Ungroup",
                isDisabled: !document.canUngroupSelection,
                fullWidth: true
            ) {
                document.ungroupSelectedElements()
                onApply()
            }
        }

        if document.canJoinSelection {
            ToolPanelLabelButton(
                title: "Join",
                prominent: true,
                fullWidth: true
            ) {
                if document.joinSelectedShapes() { onApply() }
            }
        }
    }

    private var arrangeSection: some View {
        ToolPanelJoinedActions(rows: [
            .init([
                .init(title: "Mirror") {
                    document.mirrorSelectedElements()
                    onApply()
                },
                .init(title: "Delete") {
                    document.deleteSelectedElements()
                    onApply()
                },
            ]),
            .init([
                .init(title: "Flip H") {
                    document.flipSelection(horizontal: true)
                    onApply()
                },
                .init(title: "Flip V") {
                    document.flipSelection(horizontal: false)
                    onApply()
                },
            ]),
        ])
    }

    /// Formats a display-unit value with just enough precision (tiny units like inches need more).
    private func displayString(_ value: CGFloat) -> String {
        var text = String(format: "%.4f", value)
        while text.contains(".") && (text.hasSuffix("0") || text.hasSuffix(".")) {
            text.removeLast()
        }
        return text.isEmpty ? "0" : text
    }

    private func syncThicknessText() {
        if case .uniform(let width) = document.selectedStrokeWidthSummary() {
            thicknessText = displayString(units.fromDocumentUnits(width))
        } else if let width = document.representativeSelectedStrokeWidth() {
            thicknessText = displayString(units.fromDocumentUnits(width))
        }
    }

    private func syncThicknessTextIfNeeded() {
        guard thicknessText.isEmpty
            || Double(thicknessText.trimmingCharacters(in: .whitespaces)) == nil else { return }
        syncThicknessText()
    }

    private func applyThickness() {
        let cleaned = thicknessText
            .replacingOccurrences(of: units.shortLabel, with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Double(cleaned), value > 0 else {
            syncThicknessText()
            return
        }
        let docWidth = units.toDocumentUnits(CGFloat(value))
        document.setSelectedStrokesWidth(docWidth)
        syncThicknessText()
        onApply()
    }

    private func stepThickness(by deltaDocPoints: CGFloat) {
        let base = document.representativeSelectedStrokeWidth() ?? document.strokeWidth
        document.setSelectedStrokesWidth(base + deltaDocPoints)
        syncThicknessText()
        onApply()
    }

    private func fillOpacityDisplayString(_ opacity: CGFloat) -> String {
        "\(Int((opacity * 100).rounded()))"
    }

    private func syncFillOpacity() {
        if case .uniform(let value) = document.selectedFillOpacitySummary() {
            fillOpacityText = fillOpacityDisplayString(value)
        } else if let value = document.representativeSelectedFillOpacity() {
            fillOpacityText = fillOpacityDisplayString(value)
        }
    }

    private func applyFillOpacity() {
        let cleaned = fillOpacityText
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Double(cleaned) else {
            syncFillOpacity()
            return
        }
        let opacity = min(1, max(0, CGFloat(value) / 100))
        document.setSelectedStrokesFillOpacity(opacity)
        syncFillOpacity()
        onApply()
    }

    private func stepFillOpacity(by delta: CGFloat) {
        let base = document.representativeSelectedFillOpacity() ?? VectorStroke.defaultFillOpacity
        let opacity = min(1, max(0, base + delta))
        document.setSelectedStrokesFillOpacity(opacity)
        syncFillOpacity()
        onApply()
    }

    @ViewBuilder
    private var imageOpacitySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            ToolPanelSectionLabel("Opacity")

            ToolPanelNumericStepper(
                text: $imageOpacityText,
                placeholder: "0",
                unitLabel: "%",
                onMinus: { stepImageOpacity(by: -Self.fillOpacityStep) },
                onPlus: { stepImageOpacity(by: Self.fillOpacityStep) },
                onSubmit: applyImageOpacity,
                onEditingChanged: { isEditingImageOpacity = $0 }
            )
        }
    }

    private func syncImageOpacity() {
        guard !isEditingImageOpacity else { return }
        guard let opacity = document.selectedReferenceImage?.opacity else { return }
        let text = fillOpacityDisplayString(opacity)
        if imageOpacityText != text {
            imageOpacityText = text
        }
    }

    private func applyImageOpacity() {
        let cleaned = imageOpacityText
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Double(cleaned) else {
            syncImageOpacity()
            return
        }
        let opacity = min(1, max(0, CGFloat(value) / 100))
        document.beginInteractiveEdit()
        document.setReferenceImageOpacity(opacity, recordUndo: false)
        syncImageOpacity()
        onApply()
    }

    private func stepImageOpacity(by delta: CGFloat) {
        let base = document.selectedReferenceImage?.opacity ?? 1
        let opacity = min(1, max(0, base + delta))
        document.beginInteractiveEdit()
        document.setReferenceImageOpacity(opacity, recordUndo: false)
        syncImageOpacity()
        onApply()
    }

    private func syncDegreesField() {
        guard !isEditingDegrees else { return }
        degreesText = String(format: "%.1f", displayedRotationDegrees)
    }

    private func apply() {
        guard let value = Double(degreesText.trimmingCharacters(in: .whitespaces)) else { return }
        if document.hasMultiSelection {
            applyGroupRotation(toDegrees: value)
        } else {
            setRotation(toDegrees: value)
        }
    }

    /// Multi-selection: the field is the rotation applied since the selection was made.
    /// Submitting the value already shown does not rotate again.
    private func applyGroupRotation(toDegrees value: Double) {
        let current = document.groupHandleRotationDegrees ?? 0
        let delta = value - current
        guard abs(delta) > 0.05 else { return }
        document.groupHandleRotationDegrees = current + delta
        document.rotateSelectedElements(byDegrees: delta)
        syncDegreesField()
        onApply()
    }

    private func stepRotation(by delta: Double) {
        if document.hasMultiSelection {
            let current = document.groupHandleRotationDegrees ?? 0
            document.groupHandleRotationDegrees = current + delta
            document.rotateSelectedElements(byDegrees: delta)
            syncDegreesField()
            onApply()
        } else {
            setRotation(toDegrees: currentDegrees + delta)
        }
    }

    private func setRotation(toDegrees value: Double) {
        if isImageSelected {
            document.beginInteractiveEdit()
            document.setReferenceImageRotation(
                radians: CGFloat(value * .pi / 180),
                recordUndo: false
            )
            syncDegreesField()
            onApply()
            return
        }

        if isTextSelected {
            guard let textID = document.selectedTextID else { return }
            document.beginInteractiveEdit()
            document.setTextRotation(
                id: textID,
                radians: CGFloat(value * .pi / 180),
                recordUndo: false
            )
            syncDegreesField()
            onApply()
            return
        }

        guard let strokeID = document.selectedStrokeID else { return }
        document.beginInteractiveEdit()
        document.setStrokeRotation(
            id: strokeID,
            toDegrees: value,
            pivotAnchorIndex: document.moveRotationPivotAnchorIndex,
            recordUndo: false
        )
        document.reconcileIntersectionAnchors(around: [strokeID])
        syncDegreesField()
        onApply()
    }
}

/// Full system color picker, styled like Settings and New Canvas.
private struct TextStyleColorPickerSheet: View {
    @Binding var color: Color

    var body: some View {
        SystemColorPickerSheet(color: $color)
    }
}
