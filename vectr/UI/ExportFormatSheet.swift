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

    var body: some View {
        NavigationStack {
            List {
                Section("Format") {
                    ForEach(ExportFormat.allCases) { format in
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
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(".\(format.fileExtension)")
                                    .foregroundStyle(.secondary)
                                    .font(.caption.monospaced())
                                if selectedFormat == format {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }

                if selectedFormat == .jpeg {
                    Section("Quality") {
                        Picker("Quality", selection: $quality) {
                            ForEach(ExportQuality.allCases) { level in
                                Text(level.label).tag(level)
                            }
                        }
                        .pickerStyle(.segmented)

                        Button("Export JPEG") {
                            onSelect(.jpeg, quality)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Export As")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
