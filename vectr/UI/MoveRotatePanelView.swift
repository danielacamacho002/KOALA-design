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

    @State private var degreesText = ""
    @State private var thicknessText = ""
    @State private var fillOpacity: Double = Double(VectorStroke.defaultFillOpacity)

    private var selectedStroke: VectorStroke? {
        guard let id = document.selectedStrokeID else { return nil }
        return document.stroke(with: id)
    }

    private var isTextSelected: Bool {
        document.selectedStrokeID == nil && document.selectedTextID != nil
    }

    private var selectedText: TextElement? {
        guard let id = document.selectedTextID else { return nil }
        return document.textElement(with: id)
    }

    private var currentDegrees: Double {
        if isTextSelected {
            return ShapeGeometry.normalizedRotationDegrees(selectedText?.rotation ?? 0)
        }
        return selectedStroke?.rotationDegrees ?? 0
    }

    private var pivotLabel: String {
        if let index = document.moveRotationPivotAnchorIndex {
            return "Anchor \(index + 1)"
        }
        return "Center"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            rotateSection

            if !document.selectedStrokeIDs.isEmpty {
                Divider()
                thicknessSection
            }

            if document.hasClosedFillableSelection {
                Divider()
                fillOpacitySection
            }

            if document.usesGroupTransform {
                Divider()
                multiSelectionSection
            }

            Divider()

            arrangeSection
        }
        .toolPanelChrome(width: 172)
        .onChange(of: document.selectedStrokeID) { _, _ in
            syncDegreesField()
            syncThicknessText()
            syncFillOpacity()
        }
        .onChange(of: document.selectedStrokeIDs) { _, _ in
            syncThicknessText()
            syncFillOpacity()
        }
        .onChange(of: document.selectedTextID) { _, _ in
            syncDegreesField()
        }
        .onChange(of: document.geometryRevision) { _, _ in
            syncDegreesFieldFromCurrent()
            syncThicknessTextIfNeeded()
        }
        .onAppear {
            syncDegreesField()
            syncThicknessText()
            syncFillOpacity()
        }
    }

    @ViewBuilder
    private var thicknessSection: some View {
        ToolPanelHeader("Thickness")

        HStack(spacing: 4) {
            Text("Current:")
            Text(currentThicknessText)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.caption2)
        .foregroundStyle(.secondary)

        HStack(spacing: 4) {
            ToolPanelIconButton(systemImage: "minus") {
                stepThickness(by: -Self.thicknessStepPoints)
            }

            FingerOnlyTextField(
                placeholder: units.shortLabel,
                text: $thicknessText,
                keyboardType: .decimalPad,
                fontSize: 12,
                cornerRadius: 0,
                onSubmit: applyThickness
            )
            .frame(height: 28)

            ToolPanelIconButton(systemImage: "plus") {
                stepThickness(by: Self.thicknessStepPoints)
            }
        }

        ToolPanelLabelButton(title: "Apply", fullWidth: true) {
            applyThickness()
        }
    }

    @ViewBuilder
    private var fillOpacitySection: some View {
        ToolPanelHeader("Fill opacity")

        HStack(spacing: 4) {
            Text("Current:")
            Text(currentFillOpacityText)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.caption2)
        .foregroundStyle(.secondary)

        Slider(
            value: fillOpacityBinding,
            in: 0...1,
            onEditingChanged: { editing in
                if editing {
                    // Snapshot once at drag start so the whole drag is a single undo step.
                    document.beginInteractiveEdit()
                } else {
                    onApply()
                }
            }
        )
    }

    @ViewBuilder
    private var rotateSection: some View {
        ToolPanelHeader("Rotate")

        if document.usesGroupTransform {
            Text("Enter degrees to rotate the selection around its center.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            FingerOnlyTextField(
                placeholder: "Degrees",
                text: $degreesText,
                keyboardType: .numbersAndPunctuation,
                fontSize: 13,
                cornerRadius: 0,
                onSubmit: apply
            )
            .frame(height: 30)

            HStack(spacing: 4) {
                ToolPanelLabelButton(title: "Rotate", fullWidth: true) {
                    applyGroupRotation()
                }
            }
        } else {
            Text("0° is the original drawn angle. Drag the handle or enter an absolute degree.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Current: \(String(format: "%.1f°", currentDegrees))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

            FingerOnlyTextField(
                placeholder: "Degrees",
                text: $degreesText,
                keyboardType: .numbersAndPunctuation,
                fontSize: 13,
                cornerRadius: 0,
                onSubmit: apply
            )
            .frame(height: 30)

            if !isTextSelected {
                Text("Pivot: \(pivotLabel)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                ToolPanelLabelButton(title: "Reset to 0°") {
                    resetToOriginal()
                }

                if !isTextSelected {
                    ToolPanelLabelButton(
                        title: "Center pivot",
                        isDisabled: document.moveRotationPivotAnchorIndex == nil
                    ) {
                        document.moveRotationPivotAnchorIndex = nil
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var multiSelectionSection: some View {
        ToolPanelHeader("\(document.selectionCount) selected")

        Text("Drag to move the group. Tap a shape to add or remove it.")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

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

            Text("Welds touching anchors into one shape. Unlike Group, this is permanent.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var arrangeSection: some View {
        HStack(spacing: 4) {
            ToolPanelLabelButton(title: "Duplicate", fullWidth: true) {
                let offset = max(document.grid.spacing, 1)
                document.duplicateSelectedElements(offset: CGPoint(x: offset, y: offset))
                onApply()
            }

            ToolPanelLabelButton(title: "Delete", fullWidth: true) {
                document.deleteSelectedElements()
                onApply()
            }
        }

        HStack(spacing: 4) {
            ToolPanelLabelButton(title: "Flip H", fullWidth: true) {
                document.flipSelection(horizontal: true)
                onApply()
            }

            ToolPanelLabelButton(title: "Flip V", fullWidth: true) {
                document.flipSelection(horizontal: false)
                onApply()
            }
        }
    }

    private var currentThicknessText: String {
        switch document.selectedStrokeWidthSummary() {
        case .none:
            return "—"
        case .mixed:
            return "Mixed"
        case .uniform(let width):
            return "\(displayString(units.fromDocumentUnits(width))) \(units.shortLabel)"
        }
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

    private var currentFillOpacityText: String {
        switch document.selectedFillOpacitySummary() {
        case .none:
            return "—"
        case .mixed:
            return "Mixed"
        case .uniform(let value):
            return "\(Int((value * 100).rounded()))%"
        }
    }

    /// Writing goes through this binding only for user drags; programmatic sync sets the
    /// `fillOpacity` state directly so it never rewrites the selected shapes.
    private var fillOpacityBinding: Binding<Double> {
        Binding(
            get: { fillOpacity },
            set: { newValue in
                fillOpacity = newValue
                document.setSelectedStrokesFillOpacity(CGFloat(newValue), recordUndo: false)
                onApply()
            }
        )
    }

    private func syncFillOpacity() {
        switch document.selectedFillOpacitySummary() {
        case .uniform(let value):
            fillOpacity = Double(value)
        case .mixed, .none:
            if let representative = document.representativeSelectedFillOpacity() {
                fillOpacity = Double(representative)
            }
        }
    }

    private func syncDegreesField() {
        // For a group / multi-selection the field takes a relative rotation, so start at 0.
        if document.usesGroupTransform {
            degreesText = "0"
        } else {
            degreesText = String(format: "%.1f", currentDegrees)
        }
    }

    private func syncDegreesFieldFromCurrent() {
        guard degreesText.isEmpty
            || Double(degreesText.trimmingCharacters(in: .whitespaces)) == nil else { return }
        syncDegreesField()
    }

    private func apply() {
        guard let value = Double(degreesText.trimmingCharacters(in: .whitespaces)) else { return }
        if document.usesGroupTransform {
            applyGroupRotation()
        } else {
            setRotation(toDegrees: value)
        }
    }

    private func applyGroupRotation() {
        guard let value = Double(degreesText.trimmingCharacters(in: .whitespaces)),
              abs(value) > 0 else { return }
        document.rotateSelectedElements(byDegrees: value)
        degreesText = "0"
        onApply()
    }

    private func resetToOriginal() {
        setRotation(toDegrees: 0)
    }

    private func setRotation(toDegrees value: Double) {
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
