//
//  SideToolPaletteView.swift
//  vectr
//

import SwiftUI

struct SideToolPaletteView: View {
    @Bindable var document: VectrDocument
    var onToolSelected: (ToolCategory) -> Void
    var onVariantSelected: () -> Void

    @State private var openVariantMenu: ToolCategory?

    private let iconSize: CGFloat = 34

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ToolCategory.shapeCategories, id: \.self) { category in
                toolButton(category, showsVariantMenu: category.isDrawingTool)
            }

            ToolPaletteSeparator()

            ForEach(ToolCategory.actionCategories, id: \.self) { category in
                toolButton(category, showsVariantMenu: category == .scale)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        }
    }

    @ViewBuilder
    private func toolButton(_ category: ToolCategory, showsVariantMenu: Bool) -> some View {
        let isActive = document.activeCategory == category

        let button = StudioIconButton(
            systemImage: category.systemImage,
            isActive: isActive,
            size: iconSize,
            showsSubmenu: showsVariantMenu && isActive
        ) {
            handleToolTap(category, showsVariantMenu: showsVariantMenu)
        }
        .accessibilityLabel(category.label)

        if showsVariantMenu {
            button.popover(isPresented: variantMenuBinding(for: category), arrowEdge: .top) {
                ToolVariantDropdown(
                    options: variantOptions(for: category),
                    selectedIndex: selectedVariantIndex(for: category),
                    onSelect: { index in
                        applyVariant(category: category, index: index)
                        openVariantMenu = nil
                    }
                )
                .presentationCompactAdaptation(.popover)
            }
        } else {
            button
        }
    }

    private func variantMenuBinding(for category: ToolCategory) -> Binding<Bool> {
        Binding(
            get: { openVariantMenu == category },
            set: { isPresented in
                if !isPresented, openVariantMenu == category {
                    openVariantMenu = nil
                }
            }
        )
    }

    private func handleToolTap(_ category: ToolCategory, showsVariantMenu: Bool) {
        let alreadyActive = document.activeCategory == category

        withAnimation(.easeOut(duration: 0.15)) {
            if showsVariantMenu {
                if alreadyActive {
                    openVariantMenu = openVariantMenu == category ? nil : category
                } else {
                    openVariantMenu = category
                }
            } else {
                openVariantMenu = nil
            }
        }

        document.selectTool(category)
        onToolSelected(category)

        if showsVariantMenu, !alreadyActive {
            withAnimation(.easeOut(duration: 0.15)) {
                openVariantMenu = category
            }
        }
    }

    private func variantOptions(for category: ToolCategory) -> [String] {
        switch category {
        case .line: LineVariant.allCases.map(\.label)
        case .circle: CircleVariant.allCases.map(\.label)
        case .rectangle: RectangleVariant.allCases.map(\.label)
        case .scale: ["Uniform", "Free"]
        default: []
        }
    }

    private func selectedVariantIndex(for category: ToolCategory) -> Int {
        switch category {
        case .line:
            LineVariant.allCases.firstIndex(of: document.lineVariant) ?? 0
        case .circle:
            CircleVariant.allCases.firstIndex(of: document.circleVariant) ?? 0
        case .rectangle:
            RectangleVariant.allCases.firstIndex(of: document.rectangleVariant) ?? 0
        case .scale:
            document.scaleUniform ? 0 : 1
        default:
            0
        }
    }

    private func applyVariant(category: ToolCategory, index: Int) {
        switch category {
        case .line:
            document.lineVariant = LineVariant.allCases[index]
            document.activeCategory = .line
        case .circle:
            document.circleVariant = CircleVariant.allCases[index]
            document.activeCategory = .circle
        case .rectangle:
            document.rectangleVariant = RectangleVariant.allCases[index]
            document.activeCategory = .rectangle
        case .scale:
            document.scaleUniform = index == 0
            document.activeCategory = .scale
            return
        default:
            return
        }
        onVariantSelected()
    }
}

// MARK: - Dropdown

private struct ToolVariantDropdown: View {
    let options: [String]
    let selectedIndex: Int
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, label in
                Button {
                    onSelect(index)
                } label: {
                    HStack(spacing: 10) {
                        Text(label)
                            .font(.subheadline)
                            .foregroundStyle(index == selectedIndex ? Color.accentColor : Color.primary)
                        Spacer(minLength: 16)
                        if index == selectedIndex {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < options.count - 1 {
                    Divider()
                        .padding(.leading, 14)
                }
            }
        }
        .frame(minWidth: 148)
        .padding(.vertical, 4)
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
