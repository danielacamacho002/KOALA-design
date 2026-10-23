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
    var highlightedTarget: OnboardingTarget? = nil
    @State private var isExpanded = false

    private var isSnapTourActive: Bool {
        switch highlightedTarget {
        case .snaps, .snap: return true
        default: return false
        }
    }

    private let iconSize: CGFloat = 34

    var body: some View {
        HStack(spacing: 2) {
            StudioIconButton(
                systemImage: "circle.grid.cross",
                isActive: isExpanded && !isSnapTourActive,
                size: iconSize
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
                .fill(Color.primary.opacity(0.05))
        }
        .onboardingAnchor(.snaps)
        .onboardingHighlight(highlightedTarget == .snaps, cornerRadius: 10)
        // The bar sits on the cream canvas, so icons must stay dark even when
        // the rest of the app is in dark mode (Color.primary would otherwise
        // go white and vanish).
        .environment(\.colorScheme, .light)
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
        StudioIconButton(
            systemImage: systemImage,
            isActive: isActive || highlightedTarget == .snap(kind),
            size: iconSize,
            action: action
        )
        .accessibilityLabel(snapAccessibilityLabel(kind))
        .onboardingAnchor(.snap(kind))
        .onboardingHighlight(highlightedTarget == .snap(kind))
    }

    private func constraintButton<Icon: View>(
        _ kind: SnapConstraint,
        isActive: Bool,
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        StudioIconButton(
            isActive: isActive || highlightedTarget == .snap(kind),
            size: iconSize,
            action: action,
            icon: icon
        )
        .accessibilityLabel(snapAccessibilityLabel(kind))
        .onboardingAnchor(.snap(kind))
        .onboardingHighlight(highlightedTarget == .snap(kind))
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
