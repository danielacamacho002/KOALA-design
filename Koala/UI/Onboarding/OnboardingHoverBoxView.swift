//
//  OnboardingHoverBoxView.swift
//  Koala
//
//  Sharp-cornered instructional hover box matching tool command panel chrome.
//

import SwiftUI
import UIKit

struct OnboardingHoverBoxView: View {
    let step: OnboardingStep
    let stepNumber: Int
    let stepCount: Int
    var onNext: () -> Void
    var onBack: () -> Void
    var onSkipAll: () -> Void
    var canGoBack: Bool = false

    private let panelWidth: CGFloat = 220
    private let bodyHeight: CGFloat = 56

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToolPanelHeader(step.title)
                .foregroundStyle(.black)

            Text(step.body)
                .font(.system(size: 11))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, minHeight: bodyHeight, maxHeight: bodyHeight, alignment: .topLeading)
                .lineLimit(4)

            Text("\(stepNumber) / \(stepCount)")
                .font(.caption2)
                .foregroundStyle(.black)

            HStack(spacing: 8) {
                ToolPanelLabelButton(title: "Skip all", action: onSkipAll)
                Spacer(minLength: 0)
                ToolPanelLabelButton(title: "Back", isDisabled: !canGoBack, action: onBack)
                ToolPanelLabelButton(
                    title: "Next",
                    prominent: true,
                    fill: Color(hex: "D1D1D6"),
                    action: onNext
                )
            }
        }
        .toolPanelChrome(width: panelWidth)
        .overlay {
            if step.target == .none {
                Rectangle()
                    .strokeBorder(.black, lineWidth: 1)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(step.title), step \(stepNumber) of \(stepCount)")
    }
}

/// Places the active onboarding hover box using the step’s alignment, or next to a measured target.
struct OnboardingTourOverlay: View {
    var controller: OnboardingController
    var anchors: [String: CGRect]
    var overlayFrame: CGRect

    private let panelWidth: CGFloat = 220
    private let margin: CGFloat = 12

    var body: some View {
        if controller.isActive,
           let step = controller.currentStep,
           step.target.boxPlacement != .aboveSnaps,
           step.target.boxPlacement != .besideCommandPanel {
            let origin = followOrigin(for: step)
            OnboardingHoverBoxView(
                step: step,
                stepNumber: controller.stepNumber,
                stepCount: controller.stepCount,
                onNext: { controller.advance() },
                onBack: { controller.retreat() },
                onSkipAll: { controller.skipAll() },
                canGoBack: !controller.isFirstStep
            )
            .padding(boxPadding(for: step, followOrigin: origin))
            .offset(freeFloatingScreenOffset(for: step))
            .alignmentGuide(.leading) { guide in
                guard let origin else { return guide[.leading] }
                return -origin.x
            }
            .alignmentGuide(.top) { guide in
                guard let origin else { return guide[.top] }
                return -origin.y
            }
            .id(step.id)
            .transition(.identity)
            .transaction { $0.animation = nil }
        }
    }

    private func boxPadding(for step: OnboardingStep, followOrigin: CGPoint?) -> EdgeInsets {
        switch step.target.boxPlacement {
        case .aboveSnaps:
            if let target = anchors[OnboardingTarget.snaps.anchorID], overlayFrame.width > 0 {
                return EdgeInsets(
                    top: 0,
                    leading: max(margin, target.minX - overlayFrame.minX),
                    bottom: max(8, overlayFrame.maxY - target.minY + 8),
                    trailing: margin
                )
            }
            return step.padding

        case .trailingPark:
            return EdgeInsets(top: 56, leading: 12, bottom: 0, trailing: 16)

        case .besideCommandPanel:
            if let panel = anchors[OnboardingTarget.commandPanel.anchorID], overlayFrame.width > 0 {
                return EdgeInsets(
                    top: max(8, panel.minY - overlayFrame.minY),
                    leading: panel.maxX - overlayFrame.minX + margin,
                    bottom: 0,
                    trailing: margin
                )
            }
            return EdgeInsets(top: 8, leading: 150 + margin, bottom: 0, trailing: margin)

        case .followTarget:
            return followOrigin == nil ? step.padding : EdgeInsets()
        }
    }

    /// Moves the centered intro from the middle of the canvas (below the toolbar,
    /// where the grid sits) to the middle of the window.
    private func freeFloatingScreenOffset(for step: OnboardingStep) -> CGSize {
        guard step.target == .none,
              overlayFrame.width > 0, overlayFrame.height > 0,
              let window = Self.keyWindow
        else { return .zero }

        let windowOnScreen = window.convert(window.bounds, to: window.screen.coordinateSpace)
        let overlayCenter = CGPoint(x: overlayFrame.midX, y: overlayFrame.midY)
        let screenFrame = windowOnScreen.contains(overlayCenter) ? windowOnScreen : window.bounds
        return CGSize(
            width: screenFrame.midX - overlayCenter.x,
            height: screenFrame.midY - overlayCenter.y
        )
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    /// Top-leading origin used only when the box follows a measured toolbar target.
    private func followOrigin(for step: OnboardingStep) -> CGPoint? {
        guard step.target.boxPlacement == .followTarget,
              step.target != .none,
              let target = anchors[step.target.anchorID],
              overlayFrame.width > 0
        else { return nil }

        switch step.target {
        case .designChip:
            let y = max(8, target.maxY - overlayFrame.minY + 8)
            return CGPoint(x: trailingLeading(aligningTo: target), y: y)

        case .printTool, .export:
            let x = clampedLeading(centeringOn: target)
            let y = max(8, target.maxY - overlayFrame.minY + 8)
            return CGPoint(x: x, y: y)

        default:
            return nil
        }
    }

    private func clampedLeading(centeringOn target: CGRect) -> CGFloat {
        let centered = target.midX - overlayFrame.minX - panelWidth / 2
        let maxX = max(margin, overlayFrame.width - panelWidth - margin)
        return min(max(margin, centered), maxX)
    }

    /// Leading edge that puts the box’s trailing edge on the icon’s trailing edge.
    private func trailingLeading(aligningTo target: CGRect) -> CGFloat {
        let maxX = max(margin, overlayFrame.width - panelWidth - margin)
        guard target.width > 1 else { return maxX }
        let aligned = target.maxX - overlayFrame.minX - panelWidth
        return min(max(margin, aligned), maxX)
    }
}

/// Global frames of tour targets, reported by toolbar buttons and the command panel.
struct OnboardingAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(
        value: inout [String: CGRect],
        nextValue: () -> [String: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// Global frame of the canvas overlay that hosts the hover box.
struct OnboardingOverlayFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

extension View {
    /// Hosts the onboarding hover box pinned to the current step’s alignment or target.
    func onboardingTourOverlay(
        controller: OnboardingController,
        anchors: [String: CGRect] = [:],
        overlayFrame: CGRect = .zero
    ) -> some View {
        let alignment: Alignment = {
            guard let step = controller.currentStep else { return .topLeading }
            switch step.target.boxPlacement {
            case .aboveSnaps: return .bottomLeading
            case .trailingPark: return .topTrailing
            case .besideCommandPanel: return .topLeading
            case .followTarget:
                let hasAnchor = anchors[step.target.anchorID] != nil && overlayFrame.width > 0
                return step.target == .none || !hasAnchor ? step.alignment : .topLeading
            }
        }()

        return overlay(alignment: alignment) {
            OnboardingTourOverlay(
                controller: controller,
                anchors: anchors,
                overlayFrame: overlayFrame
            )
            .transaction { $0.animation = nil }
        }
        .animation(nil, value: controller.stepIndex)
        .animation(nil, value: controller.isActive)
        .background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: OnboardingOverlayFrameKey.self,
                    value: geo.frame(in: .global)
                )
            }
        }
    }

    /// Reports this view’s global frame as a tour target.
    func onboardingAnchor(_ target: OnboardingTarget) -> some View {
        background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: OnboardingAnchorPreferenceKey.self,
                    value: [target.anchorID: geo.frame(in: .global)]
                )
            }
        }
    }

    /// Ring used to call out the current tour target.
    func onboardingHighlight(
        _ isHighlighted: Bool,
        cornerRadius: CGFloat = 8,
        color: Color = .white
    ) -> some View {
        overlay {
            if isHighlighted {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(color, lineWidth: 2)
            }
        }
    }
}

struct OnboardingTargetChrome: ViewModifier {
    var target: OnboardingTarget?
    var isHighlighted: Bool
    var color: Color = .white

    @ViewBuilder
    func body(content: Content) -> some View {
        if let target {
            content
                .onboardingAnchor(target)
                .onboardingHighlight(isHighlighted, color: color)
        } else {
            content
        }
    }
}
