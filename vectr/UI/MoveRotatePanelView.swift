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

    private var currentDegrees: Double {
        selectedStroke?.rotationDegrees ?? 0
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

            Text("Pivot: \(pivotLabel)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("Reset to 0°") {
                    resetToOriginal()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Center pivot") {
                    document.moveRotationPivotAnchorIndex = nil
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(document.moveRotationPivotAnchorIndex == nil)
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
        guard let strokeID = document.selectedStrokeID,
              let value = Double(degreesText.trimmingCharacters(in: .whitespaces)) else { return }

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

    private func resetToOriginal() {
        guard let strokeID = document.selectedStrokeID else { return }
        document.beginInteractiveEdit()
        document.setStrokeRotation(
            id: strokeID,
            toDegrees: 0,
            pivotAnchorIndex: document.moveRotationPivotAnchorIndex,
            recordUndo: false
        )
        document.reconcileIntersectionAnchors(around: [strokeID])
        syncDegreesField()
        onApply()
    }
}
