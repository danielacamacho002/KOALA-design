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
    @State private var columnsText = ""
    @State private var rowsText = ""

    private let gridRange = 1...10

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ToolPanelHeader("Paper")
                Spacer()
                ToolPanelCancelButton { onClose() }
            }

            VStack(alignment: .leading, spacing: 4) {
                ToolPanelSectionLabel("Size")
                paperSizeGrid
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

            VStack(alignment: .leading, spacing: 4) {
                ToolPanelSectionLabel("Columns")
                ToolPanelNumericStepper(
                    text: $columnsText,
                    placeholder: "1",
                    keyboardType: .numberPad,
                    onMinus: { stepColumns(by: -1) },
                    onPlus: { stepColumns(by: 1) },
                    onSubmit: applyColumns
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                ToolPanelSectionLabel("Rows")
                ToolPanelNumericStepper(
                    text: $rowsText,
                    placeholder: "1",
                    keyboardType: .numberPad,
                    onMinus: { stepRows(by: -1) },
                    onPlus: { stepRows(by: 1) },
                    onSubmit: applyRows
                )
            }
        }
        .toolPanelChrome(width: 172)
        .onAppear {
            syncCustomFields()
            syncGridFields()
        }
        .onChange(of: document.printLayout.paperSize) { _, _ in syncCustomFields() }
        .onChange(of: document.printLayoutRevision) { _, _ in syncGridFieldsIfIdle() }
    }

    // MARK: - Paper size grid

    private var paperSizeGrid: some View {
        VStack(spacing: 0) {
            paperSizeRow(.letter, .a4)
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 1)
            paperSizeRow(.legal, .custom)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.toolPanelButtonFill)
    }

    private func paperSizeRow(_ leading: PaperSize, _ trailing: PaperSize) -> some View {
        HStack(spacing: 0) {
            paperSizeButton(leading)
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 1, height: 16)
            paperSizeButton(trailing)
        }
    }

    private func paperSizeButton(_ size: PaperSize) -> some View {
        ToolPanelLabelButton(
            title: size.label,
            prominent: document.printLayout.paperSize == size,
            fullWidth: true
        ) {
            selectSize(size)
        }
    }

    // MARK: - Grid

    private func stepColumns(by delta: Int) {
        let next = clampedGrid(document.printLayout.clampedColumns + delta)
        updateGrid(columns: next)
        columnsText = "\(next)"
    }

    private func stepRows(by delta: Int) {
        let next = clampedGrid(document.printLayout.clampedRows + delta)
        updateGrid(rows: next)
        rowsText = "\(next)"
    }

    private func applyColumns() {
        let next = clampedGrid(Int(columnsText.trimmingCharacters(in: .whitespaces)) ?? document.printLayout.clampedColumns)
        updateGrid(columns: next)
        columnsText = "\(next)"
    }

    private func applyRows() {
        let next = clampedGrid(Int(rowsText.trimmingCharacters(in: .whitespaces)) ?? document.printLayout.clampedRows)
        updateGrid(rows: next)
        rowsText = "\(next)"
    }

    private func clampedGrid(_ value: Int) -> Int {
        min(gridRange.upperBound, max(gridRange.lowerBound, value))
    }

    private func syncGridFields() {
        columnsText = "\(document.printLayout.clampedColumns)"
        rowsText = "\(document.printLayout.clampedRows)"
    }

    /// Refreshes the fields from the model, but never clobbers a value the user is typing.
    private func syncGridFieldsIfIdle() {
        if columnsText.isEmpty || Int(columnsText.trimmingCharacters(in: .whitespaces)) == nil {
            columnsText = "\(document.printLayout.clampedColumns)"
        }
        if rowsText.isEmpty || Int(rowsText.trimmingCharacters(in: .whitespaces)) == nil {
            rowsText = "\(document.printLayout.clampedRows)"
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
