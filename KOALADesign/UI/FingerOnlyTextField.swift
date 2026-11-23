//
//  FingerOnlyTextField.swift
//  Koala
//

import SwiftUI
import UIKit

private final class FingerOnlyUITextField: UITextField {
    override init(frame: CGRect) {
        super.init(frame: frame)
        PencilTextEntry.install()
        PencilTextEntry.suppressHandwriting(on: self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        PencilTextEntry.suppressHandwriting(on: self)
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
    var backgroundColor: UIColor = .secondarySystemBackground
    var textAlignment: NSTextAlignment = .natural
    var trailingLabel: String? = nil
    var onSubmit: (() -> Void)?
    var onEditingEnded: (() -> Void)?
    var onEditingChanged: ((Bool) -> Void)? = nil

    func makeUIView(context: Context) -> UITextField {
        let field = FingerOnlyUITextField()
        field.delegate = context.coordinator
        field.placeholder = placeholder
        field.font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        field.borderStyle = .none
        field.backgroundColor = backgroundColor
        field.textColor = .white
        field.tintColor = .white
        field.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor.white.withAlphaComponent(0.45)]
        )
        field.textAlignment = textAlignment
        field.layer.cornerRadius = cornerRadius
        field.keyboardType = keyboardType
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        applyTrailingLabel(to: field)
        field.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        uiView.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor.white.withAlphaComponent(0.45)]
        )
        uiView.keyboardType = keyboardType
        uiView.font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        uiView.backgroundColor = backgroundColor
        uiView.textColor = .white
        uiView.tintColor = .white
        uiView.textAlignment = textAlignment
        uiView.layer.cornerRadius = cornerRadius
        applyTrailingLabel(to: uiView)
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onEditingEnded = onEditingEnded
        context.coordinator.onEditingChanged = onEditingChanged
    }

    private func applyTrailingLabel(to field: UITextField) {
        guard let trailingLabel, !trailingLabel.isEmpty else {
            field.rightView = nil
            field.rightViewMode = .never
            return
        }
        let font = UIFont.systemFont(ofSize: 10)
        let textWidth = ceil((trailingLabel as NSString).size(withAttributes: [.font: font]).width)
        let pad: CGFloat = 3
        let height = ceil(font.lineHeight)
        let container = UIView(frame: CGRect(x: 0, y: 0, width: textWidth + pad, height: height))
        let unit = UILabel(frame: CGRect(x: pad, y: 0, width: textWidth, height: height))
        unit.text = trailingLabel
        unit.font = font
        unit.textColor = UIColor.white.withAlphaComponent(0.65)
        unit.isUserInteractionEnabled = false
        container.isUserInteractionEnabled = false
        container.addSubview(unit)
        field.rightView = container
        field.rightViewMode = .always
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            onSubmit: onSubmit,
            onEditingEnded: onEditingEnded,
            onEditingChanged: onEditingChanged
        )
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        var onSubmit: (() -> Void)?
        var onEditingEnded: (() -> Void)?
        var onEditingChanged: ((Bool) -> Void)?

        init(
            text: Binding<String>,
            onSubmit: (() -> Void)?,
            onEditingEnded: (() -> Void)?,
            onEditingChanged: ((Bool) -> Void)?
        ) {
            _text = text
            self.onSubmit = onSubmit
            self.onEditingEnded = onEditingEnded
            self.onEditingChanged = onEditingChanged
        }

        @objc func textChanged(_ sender: UITextField) {
            text = sender.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            onEditingChanged?(true)
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            onSubmit?()
            return true
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            onEditingChanged?(false)
            onEditingEnded?()
        }
    }
}
