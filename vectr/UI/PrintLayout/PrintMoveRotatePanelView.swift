//
//  PrintMoveRotatePanelView.swift
//  vectr
//

import SwiftUI

/// Command panel shown when an element is selected in Print Layout. Mirrors the
/// design-mode Rotate panel: absolute-degree input where 0 is the original
/// drawn angle, a reset, and an opt-in rotate mode that reveals the drag handle.
struct PrintMoveRotatePanelView: View {
    @Bindable var document: VectrDocument
    @Binding var rotateModeActive: Bool
    var onChanged: () -> Void
    var onClose: () -> Void

    @State private var degreesText = ""

    private var selectedID: UUID? {
        document.printSelectedStrokeID ?? document.printSelectedTextID
    }

    private var currentDegrees: Double {
        guard let id = selectedID else { return 0 }
        return ShapeGeometry.normalizedRotationDegrees(document.printTransform(for: id).rotation)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ToolPanelHeader("Rotate")
                Spacer()
                ToolPanelCancelButton { onClose() }
            }

            Text("0° is the original drawn angle. Enter a degree or tap Rotate to drag the handle.")
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

            HStack(spacing: 4) {
                ToolPanelLabelButton(title: "Reset to 0°") {
                    setRotation(toDegrees: 0)
                }

                ToolPanelLabelButton(
                    title: rotateModeActive ? "Rotating" : "Rotate",
                    prominent: rotateModeActive
                ) {
                    rotateModeActive.toggle()
                }
            }

            Divider()

            ToolPanelSectionLabel("Flip")
            HStack(spacing: 4) {
                ToolPanelLabelButton(title: "Flip H", fullWidth: true) {
                    toggleFlip(horizontal: true)
                }
                ToolPanelLabelButton(title: "Flip V", fullWidth: true) {
                    toggleFlip(horizontal: false)
                }
            }
        }
        .toolPanelChrome(width: 208)
        .onAppear { syncDegreesField() }
        .onChange(of: document.printSelectedStrokeID) { _, _ in syncDegreesField() }
        .onChange(of: document.printSelectedTextID) { _, _ in syncDegreesField() }
        .onChange(of: document.printLayoutRevision) { _, _ in syncDegreesFieldFromCurrent() }
    }

    private func syncDegreesField() {
        degreesText = String(format: "%.1f", currentDegrees)
    }

    /// Keeps the field in sync with live changes, but never clobbers a value the
    /// user is actively typing (only refreshes when empty or non-numeric).
    private func syncDegreesFieldFromCurrent() {
        guard degreesText.isEmpty
            || Double(degreesText.trimmingCharacters(in: .whitespaces)) == nil else { return }
        syncDegreesField()
    }

    private func apply() {
        guard let value = Double(degreesText.trimmingCharacters(in: .whitespaces)) else { return }
        setRotation(toDegrees: value)
    }

    private func setRotation(toDegrees value: Double) {
        guard let id = selectedID else { return }
        document.beginInteractiveEdit()
        var transform = document.printTransform(for: id)
        transform.rotation = CGFloat(value * .pi / 180)
        document.setPrintTransform(transform, for: id, recordUndo: false)
        syncDegreesField()
        onChanged()
    }

    private func toggleFlip(horizontal: Bool) {
        guard let id = selectedID else { return }
        document.beginInteractiveEdit()
        var transform = document.printTransform(for: id)
        if horizontal {
            transform.flipHorizontal.toggle()
        } else {
            transform.flipVertical.toggle()
        }
        document.setPrintTransform(transform, for: id, recordUndo: false)
        onChanged()
    }
}
