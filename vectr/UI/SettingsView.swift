//
//  SettingsView.swift
//  vectr
//

import SwiftUI

struct SettingsView: View {
    @Bindable var document: VectrDocument
    @Binding var fileName: String
    var onFileNameChanged: () -> Void
    var onReplayTutorial: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var editingName = ""
    @State private var gridSpacingDisplay: Double = 20
    @State private var cornerRadiusDisplay: Double = 0
    @State private var thicknessDisplay: Double = 1.5

    @AppStorage(AppearanceSettings.canvasColorKey) private var canvasColorHex = AppearanceSettings.defaultCanvasHex

    var body: some View {
        NavigationStack {
            Form {
                Section("Project") {
                    TextField("Project name", text: $editingName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }

                Section("Units") {
                    Picker("Measurement", selection: $document.settings.units) {
                        ForEach(MeasurementUnit.allCases) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                    .onChange(of: document.settings.units) { _, _ in
                        document.settings.syncCanvasExtentToMaximum()
                        reloadDisplayValues()
                        document.syncGridFromSettings()
                    }
                }

                Section("Input") {
                    Toggle("Allow finger drawing", isOn: $document.settings.allowsFingerDrawing)
                    Text("Apple Pencil input always remains enabled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Appearance") {
                    ColorSettingRow(
                        title: "Canvas color",
                        selectedHex: $canvasColorHex,
                        presets: AppearanceSettings.canvasPresets
                    )
                }

                Section("Canvas & grid") {
                    LabeledContent("Grid spacing") {
                        HStack {
                            Slider(value: $gridSpacingDisplay, in: gridRange, step: gridStep)
                            Text(formatted(gridSpacingDisplay, unit: document.settings.units.shortLabel))
                                .monospacedDigit()
                                .frame(width: 56, alignment: .trailing)
                        }
                    }
                    .onChange(of: gridSpacingDisplay) { _, value in
                        document.settings.defaultGridSpacingInUnits = CGFloat(value)
                        document.syncGridFromSettings()
                    }

                    Picker("Snap to", selection: $document.grid.snapSubdivisions) {
                        Text("Corners").tag(1)
                        Text("Halves").tag(2)
                        Text("Quarters").tag(4)
                    }

                    Text("Snap to fractions of a grid square without changing the grid.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Lines") {
                    LabeledContent("Default thickness") {
                        HStack {
                            Slider(value: $thicknessDisplay, in: 0.5...48, step: 0.5)
                            Text(formatted(thicknessDisplay, unit: document.settings.units.shortLabel))
                                .monospacedDigit()
                                .frame(width: 56, alignment: .trailing)
                        }
                    }
                    .onChange(of: thicknessDisplay) { _, value in
                        document.strokeWidth = document.settings.units.toDocumentUnits(CGFloat(value))
                    }

                    LabeledContent("Corner fillet") {
                        HStack {
                            Slider(value: $cornerRadiusDisplay, in: 0...80, step: 1)
                            Text(formatted(cornerRadiusDisplay, unit: document.settings.units.shortLabel))
                                .monospacedDigit()
                                .frame(width: 56, alignment: .trailing)
                        }
                    }
                    .onChange(of: cornerRadiusDisplay) { _, value in
                        document.settings.defaultCornerRadius = document.settings.units.toDocumentUnits(CGFloat(value))
                    }

                    Text("New rectangles use this fillet radius from Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Help") {
                    Button("View tutorial") {
                        onReplayTutorial?()
                        dismiss()
                    }
                    Text("Replay the design tutorial. The Print Layout tutorial will show again the next time you open that mode.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        commitProjectName()
                        dismiss()
                    }
                }
            }
            .onAppear {
                editingName = fileName
                document.settings.syncCanvasExtentToMaximum()
                reloadDisplayValues()
            }
        }
    }

    private var gridRange: ClosedRange<Double> {
        switch document.settings.units {
        case .points: return 5...100
        case .millimeters: return 1...50
        case .centimeters: return 0.5...20
        case .inches: return 0.1...2
        }
    }

    private var gridStep: Double {
        switch document.settings.units {
        case .points: return 1
        case .millimeters: return 0.5
        case .centimeters: return 0.1
        case .inches: return 0.05
        }
    }

    private func commitProjectName() {
        let trimmed = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? "Untitled Artwork" : trimmed
        guard resolved != fileName else { return }
        fileName = resolved
        onFileNameChanged()
    }

    private func reloadDisplayValues() {
        gridSpacingDisplay = Double(document.settings.units.fromDocumentUnits(document.settings.defaultGridSpacing))
        cornerRadiusDisplay = Double(document.settings.units.fromDocumentUnits(document.settings.defaultCornerRadius))
        thicknessDisplay = Double(document.settings.units.fromDocumentUnits(document.strokeWidth))
    }

    private func formatted(_ value: Double, unit: String) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(value)) \(unit)"
        }
        return String(format: "%.1f %@", value, unit)
    }
}

private struct ColorSettingRow: View {
    let title: String
    @Binding var selectedHex: String
    let presets: [String]

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                ForEach(presets, id: \.self) { preset in
                    let isSelected = preset.caseInsensitiveCompare(selectedHex) == .orderedSame
                    Button {
                        selectedHex = preset
                    } label: {
                        Circle()
                            .fill(Color(hex: preset))
                            .frame(width: 24, height: 24)
                            .overlay {
                                Circle().strokeBorder(
                                    isSelected ? Color.accentColor : Color.primary.opacity(0.15),
                                    lineWidth: isSelected ? 3 : 1
                                )
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title) #\(preset)")
                }
            }
        }
    }
}
