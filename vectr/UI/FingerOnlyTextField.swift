//
//  FingerOnlyTextField.swift
//  vectr
//

import SwiftUI
import UIKit

private final class FingerOnlyUITextField: UITextField, UIScribbleInteractionDelegate {
    override init(frame: CGRect) {
        super.init(frame: frame)
        // Consume Pencil touches as plain taps but never accept handwriting.
        addInteraction(UIScribbleInteraction(delegate: self))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func scribbleInteraction(_ interaction: UIScribbleInteraction, shouldBeginAt location: CGPoint) -> Bool {
        false
    }
}

/// Text field that accepts keyboard input only. Apple Pencil can tap to focus,
/// but Scribble handwriting is disabled and Pencil strokes never pass through to the canvas.
struct FingerOnlyTextField: UIViewRepresentable {
    var placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var fontSize: CGFloat = UIFont.labelFontSize
    var cornerRadius: CGFloat = 8
    var onSubmit: (() -> Void)?
    var onEditingEnded: (() -> Void)?

    func makeUIView(context: Context) -> UITextField {
        let field = FingerOnlyUITextField()
        field.delegate = context.coordinator
        field.placeholder = placeholder
        field.font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        field.borderStyle = .none
        field.backgroundColor = .secondarySystemBackground
        field.layer.cornerRadius = cornerRadius
        field.keyboardType = keyboardType
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        uiView.placeholder = placeholder
        uiView.keyboardType = keyboardType
        uiView.font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onEditingEnded = onEditingEnded
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit, onEditingEnded: onEditingEnded)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        var onSubmit: (() -> Void)?
        var onEditingEnded: (() -> Void)?

        init(text: Binding<String>, onSubmit: (() -> Void)?, onEditingEnded: (() -> Void)?) {
            _text = text
            self.onSubmit = onSubmit
            self.onEditingEnded = onEditingEnded
        }

        @objc func textChanged(_ sender: UITextField) {
            text = sender.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            onSubmit?()
            return true
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            onEditingEnded?()
        }
    }
}
