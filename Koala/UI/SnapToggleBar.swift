//
//  SnapToggleBar.swift
//  Koala
//

import SwiftUI

/// Bottom-left canvas control for the object snapping engine. Starts as a single
/// button; tapping it reveals independent toggles for which snap types the engine
/// considers: Endpoints (square), Midpoints (triangle), Intersections (X), Center,
/// and on-rim / compass (diamond). These map directly to `PathSnapEngine`'s enabled
/// kinds via the document toggles.
struct SnapToggleBar: View {
    @Bindable var document: KoalaDocument
    /// Top-left of this chrome overlay, in canvas-view coordinates.
    var overlayOrigin: CGPoint
    var highlightedTarget: OnboardingTarget? = nil
    @State private var isExpanded = false

    private var isSnapTourActive: Bool {
        switch highlightedTarget {
        case .snaps, .snap: return true
        default: return false
        }
    }

    private let iconSize: CGFloat = 34

    /// Sheet rectangle in this overlay's coordinate space. Read from `body` so
    /// icon color tracks pan and zoom without refreshing the rest of the editor.
    private var sheetRect: CGRect {
        CanvasIconContrast.sheetRect(
            viewport: document.viewport,
            canvasSize: document.settings.canvasSize,
            overlayOrigin: overlayOrigin
        )
    }

    var body: some View {
        HStack(spacing: 2) {
            canvasIcon(
                systemImage: "circle.grid.cross",
                isActive: isExpanded && !isSnapTourActive
            ) {
                withAnimation(.easeOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            }
            .accessibilityLabel(isExpanded ? "Hide snaps" : "Show snaps")

            if isExpanded {
                snapToggles
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.05))
        }
        .onboardingAnchor(.snaps)
        .onboardingHighlight(highlightedTarget == .snaps, cornerRadius: 10, color: .accentColor)
        .onAppear {
            if isSnapTourActive { isExpanded = true }
        }
        .onChange(of: isSnapTourActive) { _, active in
            if active {
                withAnimation(.easeOut(duration: 0.15)) {
                    isExpanded = true
                }
            }
        }
    }

    @ViewBuilder
    private var snapToggles: some View {
        constraintButton(.endpoint, isActive: document.endpointSnapEnabled) {
            document.endpointSnapEnabled.toggle()
        } icon: {
            EndpointSnapIcon()
                .frame(width: 17, height: 17)
        }

        constraintButton(.midpoint, isActive: document.midpointSnapEnabled) {
            document.midpointSnapEnabled.toggle()
        } icon: {
            MidpointSnapIcon()
                .frame(width: 17, height: 17)
        }

        constraintButton(
            .intersection,
            systemImage: "xmark",
            isActive: document.intersectionSnapEnabled
        ) {
            document.intersectionSnapEnabled.toggle()
        }

        constraintButton(
            .center,
            systemImage: "smallcircle.circle",
            isActive: document.centerSnapEnabled
        ) {
            document.centerSnapEnabled.toggle()
        }

        constraintButton(.quadrant, isActive: document.quadrantSnapEnabled) {
            document.quadrantSnapEnabled.toggle()
        } icon: {
            QuadrantSnapIcon()
                .frame(width: 21, height: 21)
        }
    }

    private func constraintButton(
        _ kind: SnapConstraint,
        systemImage: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        canvasIcon(
            systemImage: systemImage,
            isActive: isActive || highlightedTarget == .snap(kind),
            action: action
        )
        .accessibilityLabel(snapAccessibilityLabel(kind))
        .onboardingAnchor(.snap(kind))
        .onboardingHighlight(highlightedTarget == .snap(kind), color: .accentColor)
    }

    private func constraintButton<Icon: View>(
        _ kind: SnapConstraint,
        isActive: Bool,
        action: @escaping () -> Void,
        @ViewBuilder icon: @escaping () -> Icon
    ) -> some View {
        canvasIcon(isActive: isActive || highlightedTarget == .snap(kind), action: action, icon: icon)
            .accessibilityLabel(snapAccessibilityLabel(kind))
            .onboardingAnchor(.snap(kind))
            .onboardingHighlight(highlightedTarget == .snap(kind), color: .accentColor)
    }

    /// Black while this glyph sits on the sheet, white once it is over the pasteboard.
    private func canvasIcon(
        systemImage: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        CanvasContrastTint(canvasRect: sheetRect) { overCanvas in
            StudioIconButton(
                systemImage: systemImage,
                isActive: isActive,
                size: iconSize,
                inactiveColor: CanvasIconContrast.iconColor(isOverCanvas: overCanvas),
                action: action
            )
        }
    }

    private func canvasIcon<Icon: View>(
        isActive: Bool,
        action: @escaping () -> Void,
        @ViewBuilder icon: @escaping () -> Icon
    ) -> some View {
        CanvasContrastTint(canvasRect: sheetRect) { overCanvas in
            StudioIconButton(
                isActive: isActive,
                size: iconSize,
                inactiveColor: CanvasIconContrast.iconColor(isOverCanvas: overCanvas),
                action: action,
                icon: icon
            )
        }
    }

    private func snapAccessibilityLabel(_ kind: SnapConstraint) -> String {
        switch kind {
        case .endpoint: return "Endpoint snap"
        case .midpoint: return "Midpoint snap"
        case .intersection: return "Intersection snap"
        case .center: return "Center point snap"
        case .quadrant: return "Circle snap"
        case .tangent: return "Tangent"
        }
    }
}
