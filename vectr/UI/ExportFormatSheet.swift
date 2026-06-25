//
//  ExportFormatSheet.swift
//  vectr
//

import SwiftUI

struct ExportFormatSheet: View {
    var onSelect: (ExportFormat) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(ExportFormat.allCases) { format in
                Button {
                    onSelect(format)
                    dismiss()
                } label: {
                    HStack {
                        Text(format.label)
                        Spacer()
                        Text(".\(format.fileExtension)")
                            .foregroundStyle(.secondary)
                            .font(.caption.monospaced())
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
        .presentationDetents([.medium])
    }
}
