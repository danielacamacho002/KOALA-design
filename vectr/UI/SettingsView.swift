//
//  SettingsView.swift
//  vectr
//

import SwiftUI

struct SettingsView: View {
    @Bindable var document: VectrDocument
    @Binding var fileName: String
    var onFileNameChanged: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var editingName = ""
    @State private var gridSpacingText = ""
    @FocusState private var gridSpacingFocused: Bool

    @AppStorage(AppearanceSettings.canvasColorKey) private var canvasColorHex = AppearanceSettings.defaultCanvasHex

    /// Pasteboard shown around the canvas sheet.
    private var pageColor: Color { Color(hex: AppearanceSettings.pasteboardHex) }
    /// Toolbar grey used for grouped setting rows.
    private var cardColor: Color { Color(hex: AppearanceSettings.toolbarHex) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    settingsCard("Project") {
                        squareTextField("Project name", text: $editingName)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .padding(12)
                    }

                    settingsCard("Units") {
                        SettingsOptionBar(
                            options: MeasurementUnit.allCases,
                            selection: $document.settings.units,
                            title: \.label
                        )
                        .onChange(of: document.settings.units) { _, _ in
                            reloadDisplayValues()
                            document.syncGridFromSettings()
                        }
                    }

                    settingsCard("Input") {
                        Toggle("Allow finger drawing", isOn: $document.settings.allowsFingerDrawing)
                            .toggleStyle(SettingsCheckboxToggleStyle())
                            .settingsInset()
                        rowDivider
                        settingsCaption("Apple Pencil input always remains enabled.")
                    }

                    settingsCard("Appearance") {
                        ColorSettingRow(
                            title: "Canvas color",
                            selectedHex: $canvasColorHex,
                            presets: AppearanceSettings.canvasPresets
                        )
                        .settingsInset()
                    }

                    settingsCard("Canvas & grid") {
                        Toggle("Show grid", isOn: $document.grid.isVisible)
                            .toggleStyle(SettingsCheckboxToggleStyle())
                            .settingsInset()
                        rowDivider
                        HStack {
                            Text("Grid spacing")
                            Spacer(minLength: 12)
                            squareTextField("Spacing", text: $gridSpacingText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .focused($gridSpacingFocused)
                                .frame(width: 88)
                                .onSubmit(commitGridSpacing)
                            Text(document.settings.units.shortLabel)
                                .foregroundStyle(.secondary)
                        }
                        .onChange(of: gridSpacingFocused) { _, focused in
                            if !focused { commitGridSpacing() }
                        }
                        .settingsInset()
                        rowDivider
                        SettingsOptionBar(
                            options: snapOptions.map(\.value),
                            selection: $document.grid.snapSubdivisions,
                            title: { value in
                                snapOptions.first { $0.value == value }?.title ?? ""
                            }
                        )
                        rowDivider
                        settingsCaption("Snap to fractions of a grid square without changing the grid. Zoom in to reveal these sub-grid lines.")
                    }
                }
                .padding(20)
            }
            .scrollContentBackground(.hidden)
            .background(pageColor)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(pageColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        commitProjectName()
                        commitGridSpacing()
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Done")
                }
            }
            .onAppear {
                editingName = fileName
                reloadDisplayValues()
            }
        }
        .background(SquareSheetCorners())
        .presentationBackground(pageColor)
        .presentationCornerRadius(0)
        .preferredColorScheme(.dark)
    }

    private var snapOptions: [(title: String, value: Int)] {
        [
            ("Corners", 1),
            ("Halves", 2),
            ("Quarters", 4),
            ("Eighths", 8),
            ("Sixteenths", 16)
        ]
    }

    private var gridRange: ClosedRange<Double> {
        switch document.settings.units {
        case .points: return 5...100
        case .millimeters: return 1...50
        case .centimeters: return 0.5...20
        case .inches: return 0.1...2
        }
    }

    private func settingsCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardColor)
        }
    }

    private func squareTextField(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text)
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.15))
            .frame(height: 1)
    }

    private func settingsCaption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .settingsInset()
    }

    private func commitProjectName() {
        let trimmed = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? "Untitled Artwork" : trimmed
        guard resolved != fileName else { return }
        fileName = resolved
        onFileNameChanged()
    }

    private func reloadDisplayValues() {
        gridSpacingText = spacingText(document.settings.defaultGridSpacingInUnits)
    }

    private func commitGridSpacing() {
        let cleaned = gridSpacingText.trimmingCharacters(in: .whitespaces)
        guard let value = Double(cleaned) else {
            gridSpacingText = spacingText(document.settings.defaultGridSpacingInUnits)
            return
        }
        let clamped = min(max(value, gridRange.lowerBound), gridRange.upperBound)
        document.settings.defaultGridSpacingInUnits = CGFloat(clamped)
        document.syncGridFromSettings()
        gridSpacingText = spacingText(CGFloat(clamped))
    }

    private func spacingText(_ value: CGFloat) -> String {
        let number = Double(value)
        if number.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(number))"
        }
        return String(format: "%g", number)
    }

}

enum SettingsSelection {
    /// System blue used for selected setting controls.
    static let blue = Color.accentColor
    /// Translucent wash so a selected bar segment reads as a highlight.
    static let highlight = blue.opacity(0.55)
}

private extension View {
    func settingsInset() -> some View {
        padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsOptionBar<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                if index > 0 {
                    Rectangle()
                        .fill(Color.white.opacity(0.22))
                        .frame(width: 1)
                }

                Button {
                    selection = option
                } label: {
                    Text(title(option))
                        .font(.body)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                        .background {
                            if selection == option {
                                SettingsSelection.highlight
                                    .shadow(color: SettingsSelection.blue.opacity(0.95), radius: 8)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .clipShape(Rectangle())
    }
}

private struct SettingsSquare: View {
    var fill: Color
    var isSelected: Bool
    var size: CGFloat = 22

    var body: some View {
        Rectangle()
            .fill(fill)
            .overlay {
                Rectangle()
                    .strokeBorder(
                        isSelected ? Color.white : Color.white.opacity(0.4),
                        lineWidth: 1
                    )
            }
            .frame(width: size, height: size)
    }
}

private struct SettingsCheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 12)
            SettingsSquare(
                fill: configuration.isOn ? SettingsSelection.blue : Color.clear,
                isSelected: configuration.isOn,
                size: 12
            )
        }
        .contentShape(Rectangle())
        .onTapGesture {
            configuration.isOn.toggle()
        }
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
                        SettingsSquare(
                            fill: Color(hex: preset),
                            isSelected: isSelected,
                            size: isSelected ? 26 : 22
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title) #\(preset)")
                }
            }
        }
    }
}
