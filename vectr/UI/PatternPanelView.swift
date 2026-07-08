//
//  PatternPanelView.swift
//  vectr
//

import SwiftUI

struct PatternPanelView: View {
    @Bindable var document: VectrDocument
    var units: MeasurementUnit
    @Binding var settings: PatternSettings
    var onPreviewChange: () -> Void
    var onApply: () -> Void
    var onStatus: (String) -> Void

    private var canApply: Bool {
        guard document.selectedStrokeID != nil,
              let stroke = document.selectedStrokeID.flatMap({ document.stroke(with: $0) }),
              let layer = document.layers.first(where: { $0.id == stroke.layerID }),
              !layer.isLocked,
              let strokeID = document.selectedStrokeID else { return false }
        let application = PatternEngine.application(
            from: stroke,
            sourceID: strokeID,
            settings: settings
        )
        return application.repositionedSource != nil || !application.newStrokes.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pattern")
                .font(.caption.weight(.semibold))

            Text("Spread the selected shape into a grid, line, radial, or spiral arrangement.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Mode", selection: $settings.mode) {
                ForEach(PatternMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: settings.mode) { _, _ in onPreviewChange() }

            modeControls

            if settings.mode == .radial || settings.mode == .spiral {
                Toggle("Keep original", isOn: $settings.keepOriginal)
                    .font(.caption2)
                    .onChange(of: settings.keepOriginal) { _, _ in onPreviewChange() }

                Toggle("Rotate copies", isOn: $settings.rotateCopies)
                    .font(.caption2)
                    .onChange(of: settings.rotateCopies) { _, _ in onPreviewChange() }
            }

            previewSummary

            Button("Apply") { apply() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!canApply)
        }
        .padding(10)
        .frame(width: 188)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemBackground).opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .onAppear {
            onPreviewChange()
        }
        .onChange(of: document.selectedStrokeID) { _, _ in
            if let id = document.selectedStrokeID,
               let stroke = document.stroke(with: id) {
                settings = PatternSettings.defaults(for: stroke)
            }
            onPreviewChange()
        }
    }

    @ViewBuilder
    private var modeControls: some View {
        switch settings.mode {
        case .grid:
            gridControls
        case .linear:
            linearControls
        case .radial:
            radialControls
        case .spiral:
            spiralControls
        }
    }

    private var gridControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            intStepperRow(label: "Rows", value: settings.rows) { value in
                settings.rows = value
                onPreviewChange()
            }
            intStepperRow(label: "Columns", value: settings.columns) { value in
                settings.columns = value
                onPreviewChange()
            }
            lengthStepperRow(label: "Spacing X", value: settings.spacingX) { value in
                settings.spacingX = value
                onPreviewChange()
            }
            lengthStepperRow(label: "Spacing Y", value: settings.spacingY) { value in
                settings.spacingY = value
                onPreviewChange()
            }
        }
    }

    private var linearControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            intStepperRow(label: "Count", value: settings.count) { value in
                settings.count = value
                onPreviewChange()
            }
            Picker("Direction", selection: $settings.linearDirection) {
                ForEach(LinearDirection.allCases) { direction in
                    Text(direction.label).tag(direction)
                }
            }
            .pickerStyle(.menu)
            .font(.caption2)
            .onChange(of: settings.linearDirection) { _, _ in onPreviewChange() }

            if settings.linearDirection == .horizontal {
                lengthStepperRow(label: "Spacing X", value: settings.spacingX) { value in
                    settings.spacingX = value
                    onPreviewChange()
                }
            } else {
                lengthStepperRow(label: "Spacing Y", value: settings.spacingY) { value in
                    settings.spacingY = value
                    onPreviewChange()
                }
            }
        }
    }

    private var radialControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            intStepperRow(label: "Count", value: settings.count) { value in
                settings.count = value
                onPreviewChange()
            }
            lengthStepperRow(label: "Start radius", value: settings.spacingX, minimum: 0) { value in
                settings.spacingX = value
                onPreviewChange()
            }
            lengthStepperRow(
                label: "Tightness",
                value: settings.tightness,
                minimum: 0,
                disabled: settings.radialSpreadEven
            ) { value in
                settings.tightness = value
                onPreviewChange()
            }
            Toggle("Spread even", isOn: $settings.radialSpreadEven)
                .font(.caption2)
                .onChange(of: settings.radialSpreadEven) { _, _ in onPreviewChange() }
        }
    }

    private var spiralControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            intStepperRow(label: "Count", value: settings.count) { value in
                settings.count = value
                onPreviewChange()
            }
            lengthStepperRow(label: "Start radius", value: settings.spacingX, minimum: 0) { value in
                settings.spacingX = value
                onPreviewChange()
            }
            lengthStepperRow(label: "Tightness", value: settings.tightness, minimum: 0) { value in
                settings.tightness = value
                onPreviewChange()
            }
        }
    }

    private var previewSummary: some View {
        Group {
            if document.selectedStrokeID == nil {
                Text("Select a shape first")
            } else if let stroke = document.selectedStrokeID.flatMap({ document.stroke(with: $0) }),
                      let layer = document.layers.first(where: { $0.id == stroke.layerID }),
                      layer.isLocked {
                Text("Layer is locked")
            } else if let stroke = document.selectedStrokeID.flatMap({ document.stroke(with: $0) }),
                      let strokeID = document.selectedStrokeID {
                let application = PatternEngine.application(
                    from: stroke,
                    sourceID: strokeID,
                    settings: settings
                )
                if settings.mode == .radial || settings.mode == .spiral {
                    if settings.keepOriginal {
                        let copies = application.newStrokes.count
                        Text("Preview: \(copies) new cop\(copies == 1 ? "y" : "ies") + original")
                    } else {
                        let total = application.newStrokes.count + (application.repositionedSource != nil ? 1 : 0)
                        Text("Preview: \(total) shape\(total == 1 ? "" : "s") total")
                    }
                } else {
                    let copies = application.newStrokes.count
                    Text("Preview: \(copies) shape\(copies == 1 ? "" : "s") total")
                }
            }
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    private func intStepperRow(
        label: String,
        value: Int,
        range: ClosedRange<Int> = 1...PatternSettings.maxCount,
        onChange: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
            Spacer(minLength: 4)
            stepperButton(systemImage: "minus", disabled: value <= range.lowerBound) {
                onChange(max(value - 1, range.lowerBound))
            }
            Text("\(value)")
                .font(.caption2.monospacedDigit())
                .frame(minWidth: 28, alignment: .center)
            stepperButton(systemImage: "plus", disabled: value >= range.upperBound) {
                onChange(min(value + 1, range.upperBound))
            }
        }
    }

    private func lengthStepperRow(
        label: String,
        value: CGFloat,
        minimum: CGFloat = 1,
        disabled: Bool = false,
        onChange: @escaping (CGFloat) -> Void
    ) -> some View {
        let displayValue = units.fromDocumentUnits(value)
        let minDisplay = units.fromDocumentUnits(minimum)
        let step = lengthStep

        return HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(disabled ? .tertiary : .primary)
            Spacer(minLength: 4)
            stepperButton(
                systemImage: "minus",
                disabled: disabled || displayValue <= minDisplay + 0.0001
            ) {
                let next = max(minDisplay, displayValue - step)
                onChange(units.toDocumentUnits(next))
            }
            Text(formattedDisplay(displayValue))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(disabled ? .tertiary : .primary)
                .frame(minWidth: 44, alignment: .center)
            stepperButton(systemImage: "plus", disabled: disabled) {
                onChange(units.toDocumentUnits(displayValue + step))
            }
        }
        .opacity(disabled ? 0.55 : 1)
    }

    private func stepperButton(
        systemImage: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .disabled(disabled)
    }

    private var lengthStep: Double {
        switch units {
        case .points: return 1
        case .millimeters: return 0.5
        case .centimeters: return 0.1
        case .inches: return 0.05
        }
    }

    private func formattedDisplay(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func apply() {
        guard let strokeID = document.selectedStrokeID else {
            onStatus("Select a shape first")
            return
        }
        switch document.applyPattern(to: strokeID, settings: settings) {
        case .success(let created):
            onStatus("Created \(created) cop\(created == 1 ? "y" : "ies")")
            onApply()
        case .noSelection:
            onStatus("Select a shape first")
        case .layerLocked:
            onStatus("Layer is locked")
        case .nothingToCreate:
            onStatus("Nothing to create with these settings")
        }
    }
}
