//
//  SideToolPaletteView.swift
//  vectr
//

import SwiftUI

struct SideToolPaletteView: View {
    @Bindable var document: VectrDocument
    var onToolSelected: (ToolCategory) -> Void
    var highlightedTarget: OnboardingTarget? = nil

    private let iconSize: CGFloat = 34

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ToolCategory.shapeCategories, id: \.self) { category in
                toolButton(category)
            }

            ToolPaletteSeparator()

            ForEach(ToolCategory.actionCategories, id: \.self) { category in
                toolButton(category)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        }
    }

    private func toolButton(_ category: ToolCategory) -> some View {
        let isHighlighted = highlightedTarget == .tool(category)
        return StudioIconButton(
            systemImage: category.systemImage,
            isActive: document.activeCategory == category,
            size: iconSize,
            inactiveColor: .white
        ) {
            document.selectTool(category)
            onToolSelected(category)
        }
        .accessibilityLabel(category.label)
        .onboardingAnchor(.tool(category))
        .onboardingHighlight(isHighlighted)
    }
}

/// Scale tool options, presented as a left-aligned command panel matching the
/// other drawing tools (uniform vs. free scaling).
struct ScaleToolPanelView: View {
    @Bindable var document: VectrDocument
    var onVariantSelected: () -> Void

    private let options = ["Uniform", "Free"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToolPanelHeader("Scale")

            VStack(spacing: 2) {
                ForEach(Array(options.enumerated()), id: \.offset) { index, label in
                    ToolPanelLabelButton(
                        title: label,
                        prominent: index == selectedIndex,
                        fullWidth: true,
                        alignment: .leading
                    ) {
                        document.scaleUniform = index == 0
                        onVariantSelected()
                    }
                }
            }
        }
        .toolPanelChrome(width: 150)
    }

    private var selectedIndex: Int {
        document.scaleUniform ? 0 : 1
    }
}

struct ToolPaletteSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 20)
            .padding(.horizontal, 4)
    }
}
