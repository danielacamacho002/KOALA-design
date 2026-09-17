//
//  ToolPanelStyle.swift
//  vectr
//
//  Shared visual language for the floating tool command panels so drawing and
//  manipulation tools stay consistent. Modeled on the shape command panel look:
//  sharp-cornered chrome, custom square icon buttons, and monospaced inputs.
//

import SwiftUI

extension Color {
    /// Fill for the non-prominent (secondary) tool panel buttons.
    static let toolPanelButtonFill = Color(hex: "F2F2F7")

    /// Foreground for content sitting on a non-prominent tool panel button.
    static let toolPanelButtonForeground = Color.black
}

extension View {
    /// Applies the standard tool panel chrome: sharp rectangle fill with a hairline
    /// stroke and consistent padding. Defaults to the shared panel color so every
    /// tool panel (shape, manipulation, dropdowns) stays unified.
    func toolPanelChrome(width: CGFloat? = nil, fill: Color? = nil) -> some View {
        modifier(ToolPanelChrome(width: width, fillOverride: fill))
    }
}

/// Shared chrome for floating tool panels.
private struct ToolPanelChrome: ViewModifier {
    var width: CGFloat?
    var fillOverride: Color?

    func body(content: Content) -> some View {
        content
            .padding(8)
            .frame(width: width)
            .background(Rectangle().fill(fillOverride ?? Color(hex: AppearanceSettings.panelHex)))
            .overlay(Rectangle().stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }
}

/// Panel title, e.g. "Rotate", "Fillet".
struct ToolPanelHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
    }
}

/// Small secondary label used above a control group, e.g. "Thickness", "Color".
struct ToolPanelSectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
    }
}

/// Square icon button matching the shape command panel's controls.
struct ToolPanelIconButton: View {
    let systemImage: String
    var prominent: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(prominent ? Color.black : Color.toolPanelButtonForeground)
                .frame(width: 26, height: 26)
                .background(prominent ? Color.accentColor : Color.toolPanelButtonFill)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
    }
}

/// Standard "cancel / clear" control shared by every tool panel.
struct ToolPanelCancelButton: View {
    let action: () -> Void

    var body: some View {
        ToolPanelIconButton(systemImage: "xmark", action: action)
            .accessibilityLabel("Cancel")
    }
}

/// Standard "apply / confirm" control shared by every tool panel.
struct ToolPanelApplyButton: View {
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        ToolPanelIconButton(
            systemImage: "checkmark",
            prominent: true,
            isDisabled: isDisabled,
            action: action
        )
        .accessibilityLabel("Apply")
    }
}

/// Hairline used between segments in joined tool-panel controls.
private struct ToolPanelSegmentDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 16)
    }
}

/// Equal-width option bar for tool variants (line / arc / construction, etc.).
struct ToolPanelSegmentBar: View {
    let options: [String]
    let selectedIndex: Int
    let action: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, label in
                let isSelected = index == selectedIndex
                if index > 0 {
                    ToolPanelSegmentDivider()
                }
                Button {
                    action(index)
                } label: {
                    Text(label)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(isSelected ? Color.black : Color.toolPanelButtonForeground)
                        .padding(.horizontal, 2)
                        .frame(maxWidth: .infinity)
                        .frame(height: 22)
                        .background(isSelected ? Color.accentColor : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .background(Color.toolPanelButtonFill)
    }
}

/// Minus / value / plus as one filled control with hairline dividers.
struct ToolPanelNumericStepper: View {
    @Binding var text: String
    var placeholder: String
    var unitLabel: String? = nil
    var onMinus: () -> Void
    var onPlus: () -> Void
    var onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            stepperButton(systemImage: "minus", action: onMinus)
                .accessibilityLabel("Decrease")

            ToolPanelSegmentDivider()

            HStack(spacing: 0) {
                Spacer(minLength: 4)

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(text.isEmpty ? placeholder : text)
                        .font(.system(size: 12, design: .monospaced))
                        .hidden()
                        .frame(width: 52, alignment: .trailing)
                        .overlay {
                            FingerOnlyTextField(
                                placeholder: placeholder,
                                text: $text,
                                keyboardType: .decimalPad,
                                fontSize: 12,
                                cornerRadius: 0,
                                backgroundColor: .clear,
                                textAlignment: .right,
                                onSubmit: onSubmit,
                                onEditingEnded: onSubmit
                            )
                        }

                    if let unitLabel {
                        Text(unitLabel)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                }

                Spacer(minLength: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 28)

            ToolPanelSegmentDivider()

            stepperButton(systemImage: "plus", action: onPlus)
                .accessibilityLabel("Increase")
        }
        .background(Color.toolPanelButtonFill)
    }

    private func stepperButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.toolPanelButtonForeground)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Full-width row that reveals a menu to the side of a command panel.
struct ToolPanelMenuButton: View {
    let title: String
    var isExpanded: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundStyle(isExpanded ? Color.black : Color.toolPanelButtonForeground)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isExpanded ? Color.black : .secondary)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(isExpanded ? Color.accentColor : Color.toolPanelButtonFill)
        }
        .buttonStyle(.plain)
    }
}

/// Text button matching the shape command panel's variant/action controls.
struct ToolPanelLabelButton: View {
    let title: String
    var prominent: Bool = false
    var isDisabled: Bool = false
    var fullWidth: Bool = false
    var alignment: Alignment = .center
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: prominent ? .semibold : .regular))
                .foregroundStyle(prominent ? Color.black : Color.toolPanelButtonForeground)
                .frame(maxWidth: fullWidth ? .infinity : nil, alignment: alignment)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(prominent ? Color.accentColor : Color.toolPanelButtonFill)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
    }
}
