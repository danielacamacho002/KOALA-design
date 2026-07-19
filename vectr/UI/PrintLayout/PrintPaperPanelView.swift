//
//  PrintPaperPanelView.swift
//  vectr
//

import SwiftUI

/// Floating command panel (matching the design-mode tool panels) for choosing
/// the paper size, entering a custom size, and editing the page grid.
struct PrintPaperPanelView: View {
    @Bindable var document: VectrDocument
    var units: MeasurementUnit
    var onChanged: () -> Void
    var onClose: () -> Void

    @State private var widthText = ""
    @State private var heightText = ""

    private let gridRange = 1...10

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ToolPanelHeader("Paper")
                Spacer()
                ToolPanelCancelButton { onClose() }
            }

            ToolPanelSectionLabel("Size")
            VStack(spacing: 4) {
                ForEach(PaperSize.allCases) { size in
                    ToolPanelLabelButton(
                        title: size.label,
                        prominent: document.printLayout.paperSize == size,
                        fullWidth: true,
                        alignment: .leading
                    ) {
                        selectSize(size)
                    }
                }
            }

            if document.printLayout.paperSize == .custom {
                ToolPanelSectionLabel("Custom size (\(units.shortLabel))")
                HStack(spacing: 4) {
                    FingerOnlyTextField(
                        placeholder: "W",
                        text: $widthText,
                        keyboardType: .decimalPad,
                        fontSize: 13,
                        cornerRadius: 0,
                        onSubmit: applyCustomSize
                    )
                    .frame(height: 28)

                    Text("×")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    FingerOnlyTextField(
                        placeholder: "H",
                        text: $heightText,
                        keyboardType: .decimalPad,
                        fontSize: 13,
                        cornerRadius: 0,
                        onSubmit: applyCustomSize
                    )
                    .frame(height: 28)
                }
                ToolPanelLabelButton(title: "Set size", prominent: true, fullWidth: true) {
                    applyCustomSize()
                }
            }

            Divider()

            ToolPanelSectionLabel("Grid")
            stepperRow(label: "Columns", value: document.printLayout.columns) { value in
                updateGrid(columns: value)
            }
            stepperRow(label: "Rows", value: document.printLayout.rows) { value in
                updateGrid(rows: value)
            }
        }
        .toolPanelChrome(width: 208)
        .onAppear { syncCustomFields() }
        .onChange(of: document.printLayout.paperSize) { _, _ in syncCustomFields() }
    }

    // MARK: - Grid

    private func stepperRow(label: String, value: Int, onChange: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
            Spacer(minLength: 4)
            ToolPanelIconButton(systemImage: "minus", isDisabled: value <= gridRange.lowerBound) {
                onChange(max(value - 1, gridRange.lowerBound))
            }
            Text("\(value)")
                .font(.caption2.monospacedDigit())
                .frame(minWidth: 24, alignment: .center)
            ToolPanelIconButton(systemImage: "plus", isDisabled: value >= gridRange.upperBound) {
                onChange(min(value + 1, gridRange.upperBound))
            }
        }
    }

    private func updateGrid(columns: Int? = nil, rows: Int? = nil) {
        var settings = document.printLayout
        if let columns { settings.columns = columns }
        if let rows { settings.rows = rows }
        document.updatePrintLayout(settings)
        onChanged()
    }

    // MARK: - Paper size

    private func selectSize(_ size: PaperSize) {
        var settings = document.printLayout
        settings.paperSize = size
        document.updatePrintLayout(settings)
        syncCustomFields()
        onChanged()
    }

    private func applyCustomSize() {
        let width = parsedPoints(widthText)
        let height = parsedPoints(heightText)
        guard let width, let height, width > 0, height > 0 else { return }
        var settings = document.printLayout
        settings.paperSize = .custom
        settings.customPaperSize = CGSize(width: width, height: height)
        document.updatePrintLayout(settings)
        onChanged()
    }

    private func parsedPoints(_ text: String) -> CGFloat? {
        guard let value = Double(text.trimmingCharacters(in: .whitespaces)) else { return nil }
        return units.toDocumentUnits(CGFloat(value))
    }

    private func syncCustomFields() {
        let size = document.printLayout.pageSizeInPoints
        widthText = String(format: "%.2f", units.fromDocumentUnits(size.width))
        heightText = String(format: "%.2f", units.fromDocumentUnits(size.height))
    }
}
