//
//  ExportFormatSheet.swift
//  vectr
//

import SwiftUI

struct ExportFormatSheet: View {
    var onSelect: (ExportFormat, ExportQuality) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedFormat: ExportFormat?
    @State private var quality: ExportQuality = .medium

    private var pageColor: Color { Color(hex: AppearanceSettings.pasteboardHex) }
    private var cardColor: Color { Color(hex: AppearanceSettings.toolbarHex) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Format")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        VStack(spacing: 0) {
                            ForEach(Array(ExportFormat.allCases.enumerated()), id: \.element.id) { index, format in
                                if index > 0 {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.15))
                                        .frame(height: 1)
                                }
                                formatRow(format)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(cardColor)
                    }

                    if selectedFormat == .jpeg {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Quality")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            SettingsOptionBar(
                                options: ExportQuality.allCases,
                                selection: $quality,
                                title: \.label
                            )
                            .background(cardColor)
                        }
                    }
                }
                .padding(20)
            }
            .scrollContentBackground(.hidden)
            .background(pageColor)
            .navigationTitle("Export As")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(pageColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel")
                }
                if selectedFormat == .jpeg {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            onSelect(.jpeg, quality)
                            dismiss()
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Export JPEG")
                    }
                }
            }
        }
        .presentationBackground(pageColor)
        .presentationCornerRadius(0)
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
    }

    private func formatRow(_ format: ExportFormat) -> some View {
        Button {
            if format == .jpeg {
                selectedFormat = format
            } else {
                onSelect(format, .medium)
                dismiss()
            }
        } label: {
            HStack {
                Text(format.label)
                Spacer()
                Text(".\(format.fileExtension)")
                    .foregroundStyle(.secondary)
                    .font(.caption.monospaced())
            }
            .font(.body)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selectedFormat == format ? SettingsSelection.highlight : Color.clear)
        }
        .buttonStyle(.plain)
    }
}
