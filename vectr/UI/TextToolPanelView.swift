//
//  TextToolPanelView.swift
//  vectr
//

import SwiftUI

/// Floating panel for entering and editing a text element's content and size.
struct TextToolPanelView: View {
    @Bindable var document: VectrDocument
    let elementID: UUID
    var onChanged: () -> Void
    var onDone: () -> Void

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ToolPanelHeader("Text")
                Spacer()
                ToolPanelApplyButton(action: onDone)
            }

            TextField("Type here", text: $text, axis: .vertical)
                .font(.system(size: 13))
                .lineLimit(1...6)
                .focused($focused)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(.secondarySystemBackground))
                .onChange(of: text) { _, newValue in
                    applyText(newValue)
                }

            HStack(spacing: 10) {
                Image(systemName: "textformat.size")
                    .foregroundStyle(.secondary)
                Slider(value: fontSizeBinding, in: 6...200, step: 1)
                Text("\(Int(currentFontSize))")
                    .font(.caption.monospacedDigit())
                    .frame(width: 32, alignment: .trailing)
            }
        }
        .toolPanelChrome(width: 264)
        .onAppear {
            text = document.textElement(with: elementID)?.text ?? ""
            DispatchQueue.main.async { focused = true }
        }
        .onChange(of: elementID) { _, _ in
            text = document.textElement(with: elementID)?.text ?? ""
        }
    }

    private var currentFontSize: CGFloat {
        document.textElement(with: elementID)?.fontSize ?? document.activeFontSize
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { Double(currentFontSize) },
            set: { newValue in
                document.activeFontSize = CGFloat(newValue)
                document.setTextFontSize(id: elementID, size: CGFloat(newValue))
                onChanged()
            }
        )
    }

    private func applyText(_ newValue: String) {
        guard var element = document.textElement(with: elementID) else { return }
        element.text = newValue
        document.updateTextElement(element, recordUndo: false)
        onChanged()
    }
}
