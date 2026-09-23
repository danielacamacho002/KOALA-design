//
//  PrintMoveRotatePanelView.swift
//  vectr
//

import SwiftUI

/// Command panel shown when an element is selected in Print Layout. Includes
/// optional axis-locked move, absolute-degree rotate, an opt-in rotate handle,
/// and flip.
struct PrintMoveRotatePanelView: View {
    @Bindable var document: VectrDocument
    @Binding var rotateModeActive: Bool
    @Binding var axisLockEnabled: Bool
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
                ToolPanelHeader("Move")
                Spacer()
                ToolPanelCancelButton { onClose() }
            }

            Text("Drag the selection to reposition it. Turn on axis lock to constrain movement to X or Y.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ToolPanelLabelButton(
                title: axisLockEnabled ? "Axis locked" : "Lock to axis",
                prominent: axisLockEnabled,
                fullWidth: true
            ) {
                axisLockEnabled.toggle()
            }

            Divider()

            ToolPanelSectionLabel("Rotate")

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
                    title: "Rotate",
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
        let ids = document.printSelectedIDs
        guard !ids.isEmpty else { return }
        document.beginInteractiveEdit()
        let target = CGFloat(value * .pi / 180)
        if ids.count == 1, let id = ids.first {
            var transform = document.printTransform(for: id)
            transform.rotation = target
            document.setPrintTransform(transform, for: id, recordUndo: false)
        } else if let bbox = document.printSelectionBoundingBox(),
                  let primary = document.printSelectedStrokeID ?? document.printSelectedTextID {
            let delta = target - document.printTransform(for: primary).rotation
            let origins = Dictionary(
                uniqueKeysWithValues: ids.map { ($0, document.printTransform(for: $0)) }
            )
            let centers = Dictionary(
                uniqueKeysWithValues: ids.compactMap { id -> (UUID, CGPoint)? in
                    let bounds = document.printBounds(for: id)
                    guard !bounds.isNull else { return nil }
                    return (id, CGPoint(x: bounds.midX, y: bounds.midY))
                }
            )
            document.rotatePrintSelection(
                by: delta,
                around: CGPoint(x: bbox.midX, y: bbox.midY),
                originTransforms: origins,
                originCenters: centers,
                recordUndo: false
            )
        }
        syncDegreesField()
        onChanged()
    }

    private func toggleFlip(horizontal: Bool) {
        guard !document.printSelectionIsEmpty else { return }
        document.beginInteractiveEdit()
        document.flipPrintSelection(horizontal: horizontal)
        onChanged()
    }
}
