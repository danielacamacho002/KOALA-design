//
//  CanvasSizeSheet.swift
//  vectr
//

import CoreGraphics
import SwiftUI

/// Prompt shown when creating a new canvas. Lets the user pick width, height, and
/// the unit those values are entered in. Leaving the fields blank falls back to the
/// default 24" × 18" canvas.
struct CanvasSizeSheet: View {
    /// Called with the resolved canvas size (in document points) and the chosen working unit.
    var onCreate: (CGSize, MeasurementUnit) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var widthText = ""
    @State private var heightText = ""
    @State private var unit: MeasurementUnit = .inches

    /// Units offered in the picker (inches default, plus centimeters and points).
    private static let selectableUnits: [MeasurementUnit] = [.inches, .centimeters, .points]

    private var defaultWidthDisplay: CGFloat {
        unit.fromDocumentUnits(DocumentSettings.defaultCanvasWidth)
    }

    private var defaultHeightDisplay: CGFloat {
        unit.fromDocumentUnits(DocumentSettings.defaultCanvasHeight)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    dimensionRow(title: "Width", text: $widthText, placeholder: defaultWidthDisplay)
                    dimensionRow(title: "Height", text: $heightText, placeholder: defaultHeightDisplay)
                } header: {
                    Text("Canvas Size")
                } footer: {
                    Text("Leave blank to use the default 24 × 18 in.")
                }

                Section("Units") {
                    Picker("Units", selection: $unit) {
                        ForEach(Self.selectableUnits) { unit in
                            Text(unit.shortLabel).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("New Canvas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func dimensionRow(title: String, text: Binding<String>, placeholder: CGFloat) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(formatted(placeholder), text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120)
            Text(unit.shortLabel)
                .foregroundStyle(.secondary)
        }
    }

    private func create() {
        onCreate(resolvedSize(), unit)
        dismiss()
    }

    private func resolvedSize() -> CGSize {
        CGSize(
            width: resolvedDimension(text: widthText, defaultPoints: DocumentSettings.defaultCanvasWidth),
            height: resolvedDimension(text: heightText, defaultPoints: DocumentSettings.defaultCanvasHeight)
        )
    }

    private func resolvedDimension(text: String, defaultPoints: CGFloat) -> CGFloat {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let value = Double(trimmed), value > 0 else { return defaultPoints }
        let points = unit.toDocumentUnits(CGFloat(value))
        let maxPoints = DocumentSettings.maximumCanvasExtent(for: unit)
        return min(max(points, 1), maxPoints)
    }

    private func formatted(_ value: CGFloat) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }
}
