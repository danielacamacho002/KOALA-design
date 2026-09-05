//
//  OnboardingHoverBoxView.swift
//  vectr
//
//  Sharp-cornered instructional hover box matching tool command panel chrome.
//

import SwiftUI

struct OnboardingHoverBoxView: View {
    let step: OnboardingStep
    let stepNumber: Int
    let stepCount: Int
    var onNext: () -> Void
    var onSkipAll: () -> Void

    private let panelWidth: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToolPanelHeader(step.title)
                .foregroundStyle(.white)

            Text(step.body)
                .font(.system(size: 11))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(stepNumber) / \(stepCount)")
                .font(.caption2)
                .foregroundStyle(.white)

            HStack(spacing: 8) {
                ToolPanelLabelButton(title: "Skip all", action: onSkipAll)
                Spacer(minLength: 0)
                ToolPanelLabelButton(title: "Next", prominent: true, action: onNext)
            }
        }
        .toolPanelChrome(width: panelWidth)
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
        if controller.isActive, let step = controller.currentStep {
            OnboardingHoverBoxView(
                step: step,
                stepNumber: controller.stepNumber,
                stepCount: controller.stepCount,
                onNext: { controller.advance() },
                onSkipAll: { controller.skipAll() }
            )
            .padding(boxOrigin(for: step) == nil ? step.padding : EdgeInsets())
            .alignmentGuide(.leading) { guide in
                guard let origin = boxOrigin(for: step) else { return guide[.leading] }
                return -origin.x
            }
            .alignmentGuide(.top) { guide in
                guard let origin = boxOrigin(for: step) else { return guide[.top] }
                return -origin.y
            }
            .transition(.opacity.combined(with: .move(edge: .leading)))
        }
    }

    /// Top-leading origin of the hover box in overlay coordinates, when a target is measured.
    private func boxOrigin(for step: OnboardingStep) -> CGPoint? {
        guard step.target != .none,
              let target = anchors[step.target.anchorID],
              overlayFrame.width > 0
        else { return nil }

        switch step.target {
        case .commandPanel:
            let x = target.maxX - overlayFrame.minX + margin
            let y = max(8, target.minY - overlayFrame.minY)
            if x + panelWidth > overlayFrame.width - margin {
                return CGPoint(
                    x: margin,
                    y: max(8, target.maxY - overlayFrame.minY + 8)
                )
            }
            return CGPoint(x: x, y: y)

        case .layers:
            let x = target.minX - overlayFrame.minX - panelWidth - margin
            let y = max(8, target.minY - overlayFrame.minY)
            if x < margin {
                return CGPoint(
                    x: max(margin, overlayFrame.width - panelWidth - margin),
                    y: max(8, target.maxY - overlayFrame.minY + 8)
                )
            }
            return CGPoint(x: x, y: y)

        case .snaps:
            let estimatedHeight: CGFloat = 156
            let x = clampedLeading(centeringOn: target)
            let aboveY = target.minY - overlayFrame.minY - estimatedHeight - 8
            if aboveY >= 8 {
                return CGPoint(x: x, y: aboveY)
            }
            return CGPoint(
                x: min(max(margin, target.maxX - overlayFrame.minX + margin), overlayFrame.width - panelWidth - margin),
                y: max(8, target.minY - overlayFrame.minY)
            )

        case .tool, .share, .save, .printLayout,
             .modes, .paperGrid, .margins, .printTool, .export, .designChip:
            let x = clampedLeading(centeringOn: target)
            let y = max(8, target.maxY - overlayFrame.minY + 8)
            return CGPoint(x: x, y: y)

        case .none:
            return nil
        }
    }

    private func clampedLeading(centeringOn target: CGRect) -> CGFloat {
        let centered = target.midX - overlayFrame.minX - panelWidth / 2
        let maxX = max(margin, overlayFrame.width - panelWidth - margin)
        return min(max(margin, centered), maxX)
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
            let hasAnchor = anchors[step.target.anchorID] != nil && overlayFrame.width > 0
            return step.target == .none || !hasAnchor ? step.alignment : .topLeading
        }()

        return overlay(alignment: alignment) {
            OnboardingTourOverlay(
                controller: controller,
                anchors: anchors,
                overlayFrame: overlayFrame
            )
            .animation(.easeInOut(duration: 0.15), value: controller.stepIndex)
            .animation(.easeInOut(duration: 0.15), value: controller.isActive)
        }
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
                    .stroke(color, lineWidth: 2)
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
