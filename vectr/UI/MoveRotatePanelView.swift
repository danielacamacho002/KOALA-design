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
            Text("Rotate")
                .font(.caption.weight(.semibold))

            Text("0° is the original drawn angle. Drag the handle or enter an absolute degree.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Current: \(String(format: "%.1f°", currentDegrees))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                FingerOnlyTextField(
                    placeholder: "Degrees",
                    text: $degreesText,
                    keyboardType: .numbersAndPunctuation,
                    onSubmit: apply
                )
                .frame(height: 36)
                .padding(.horizontal, 10)

                Button(action: apply) {
                    Image(systemName: "return")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if !isTextSelected {
                Text("Pivot: \(pivotLabel)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button("Reset to 0°") {
                    resetToOriginal()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if !isTextSelected {
                    Button("Center pivot") {
                        document.moveRotationPivotAnchorIndex = nil
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(document.moveRotationPivotAnchorIndex == nil)
                }
            }
        }
        .padding(10)
        .frame(width: 172)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemBackground).opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
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

    private func syncDegreesField() {
        degreesText = String(format: "%.1f", currentDegrees)
    }

    private func syncDegreesFieldFromCurrent() {
        guard degreesText.isEmpty
            || Double(degreesText.trimmingCharacters(in: .whitespaces)) == nil else { return }
        syncDegreesField()
    }

    private func apply() {
        guard let value = Double(degreesText.trimmingCharacters(in: .whitespaces)) else { return }
        setRotation(toDegrees: value)
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
