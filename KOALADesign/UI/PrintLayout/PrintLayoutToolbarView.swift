//
//  PrintLayoutToolbarView.swift
//  Koala
//

import SwiftUI

struct PrintLayoutToolbarView: View {
    @Bindable var document: KoalaDocument
    @Binding var isPaperPanelOpen: Bool
    @Binding var isMarginPanelOpen: Bool
    var canUndo: Bool
    var canRedo: Bool
    var onBack: () -> Void
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onSwitchToDesign: () -> Void
    var onExport: () -> Void
    var onSettingsChanged: () -> Void
    var highlightedTarget: OnboardingTarget? = nil

    private let toolbarHeight: CGFloat = 48
    private let iconSize: CGFloat = 34

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.medium))
                    .frame(width: 32, height: toolbarHeight)
            }
            .buttonStyle(.plain)

            ToolPaletteSeparator()
                .padding(.horizontal, 8)

            paperButton

            marginsButton

            ToolPaletteSeparator()
                .padding(.horizontal, 8)

            toolButtons

            Spacer(minLength: 8)

            ToolPaletteSeparator()
                .padding(.horizontal, 8)

            HStack(spacing: 4) {
                toolbarIconButton("arrow.uturn.backward", disabled: !canUndo, action: onUndo)
                toolbarIconButton("arrow.uturn.forward", disabled: !canRedo, action: onRedo)
                toolbarIconButton("pencil.tip", action: onSwitchToDesign, accessibilityLabel: "Design")
                    .modifier(
                        OnboardingTargetChrome(
                            target: .modes,
                            isHighlighted: highlightedTarget == .modes,
                            color: .accentColor
                        )
                    )
                    .modifier(
                        OnboardingTargetChrome(
                            target: .designChip,
                            isHighlighted: highlightedTarget == .designChip,
                            color: .accentColor
                        )
                    )
                toolbarIconButton("square.and.arrow.up", action: onExport, accessibilityLabel: "Export Tiled PDF")
                    .modifier(
                        OnboardingTargetChrome(
                            target: .export,
                            isHighlighted: highlightedTarget == .export,
                            color: .accentColor
                        )
                    )
            }
        }
        .padding(.horizontal, 12)
        .frame(height: toolbarHeight)
        .background(Color(hex: AppearanceSettings.toolbarHex))
        .foregroundStyle(.white)
    }

    private var paperButton: some View {
        StudioIconButton(
            systemImage: "doc",
            isActive: isPaperPanelOpen,
            size: iconSize,
            inactiveColor: .white
        ) {
            isPaperPanelOpen.toggle()
            if isPaperPanelOpen { isMarginPanelOpen = false }
        }
        .accessibilityLabel("Paper & Grid")
        .modifier(
            OnboardingTargetChrome(
                target: .paperGrid,
                isHighlighted: highlightedTarget == .paperGrid,
                color: .accentColor
            )
        )
    }

    private var marginsButton: some View {
        StudioIconButton(
            systemImage: "rectangle.dashed",
            isActive: isMarginPanelOpen || document.printLayout.marginMode.showsOverlay,
            size: iconSize,
            inactiveColor: .white
        ) {
            isMarginPanelOpen.toggle()
            if isMarginPanelOpen { isPaperPanelOpen = false }
        }
        .accessibilityLabel("Margins & Print Border")
        .modifier(
            OnboardingTargetChrome(
                target: .margins,
                isHighlighted: highlightedTarget == .margins,
                color: .accentColor
            )
        )
    }

    private var toolButtons: some View {
        HStack(spacing: 2) {
            ForEach(PrintLayoutTool.allCases, id: \.self) { tool in
                StudioIconButton(
                    systemImage: tool.systemImage,
                    isActive: document.printLayout.activeTool == tool,
                    size: iconSize,
                    inactiveColor: .white
                ) {
                    var settings = document.printLayout
                    settings.activeTool = tool
                    document.updatePrintLayout(settings, recordUndo: false)
                    onSettingsChanged()
                }
                .accessibilityLabel(tool.label)
                .modifier(
                    OnboardingTargetChrome(
                        target: .printTool(tool),
                        isHighlighted: highlightedTarget == .printTool(tool),
                        color: .accentColor
                    )
                )
            }
        }
    }

    private func toolbarIconButton(
        _ systemImage: String,
        disabled: Bool = false,
        action: @escaping () -> Void,
        accessibilityLabel: String? = nil
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .frame(width: 32, height: toolbarHeight)
                .opacity(disabled ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(accessibilityLabel ?? systemImage)
    }
}
