//
//  MoveRotatePanelView.swift
//  vectr
//

import SwiftUI

struct MoveRotatePanelView: View {
    @Bindable var document: VectrDocument
    var onApply: () -> Void

    @State private var degreesText = ""

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

            if document.hasMultiSelection {
                Divider()
                multiSelectionSection
            }

            Divider()

            arrangeSection
        }
        .toolPanelChrome(width: 172)
        .onChange(of: document.selectedStrokeID) { _, _ in
            syncDegreesField()
        }
        .onChange(of: document.selectedTextID) { _, _ in
            syncDegreesField()
        }
        .onChange(of: document.geometryRevision) { _, _ in
            syncDegreesFieldFromCurrent()
        }
        .onAppear {
            syncDegreesField()
        }
    }

    @ViewBuilder
    private var rotateSection: some View {
        ToolPanelHeader("Rotate")

        if document.hasMultiSelection {
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

        if document.canJoinSelection {
            ToolPanelLabelButton(title: "Join paths", prominent: true, fullWidth: true) {
                if document.joinSelectedPaths() { onApply() }
            }
        }

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

    private func syncDegreesField() {
        // For a multi-selection the field takes a relative rotation, so start at 0.
        if document.hasMultiSelection {
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
        if document.hasMultiSelection {
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
