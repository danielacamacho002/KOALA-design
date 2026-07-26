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

/// Places the active onboarding hover box using the step’s alignment and padding.
struct OnboardingTourOverlay: View {
    var controller: OnboardingController

    var body: some View {
        if controller.isActive, let step = controller.currentStep {
            OnboardingHoverBoxView(
                step: step,
                stepNumber: controller.stepNumber,
                stepCount: controller.stepCount,
                onNext: { controller.advance() },
                onSkipAll: { controller.skipAll() }
            )
            .padding(step.padding)
            .transition(.opacity.combined(with: .move(edge: .leading)))
        }
    }
}

extension View {
    /// Hosts the onboarding hover box pinned to the current step’s alignment.
    func onboardingTourOverlay(controller: OnboardingController) -> some View {
        overlay(alignment: controller.currentStep?.alignment ?? .topLeading) {
            OnboardingTourOverlay(controller: controller)
                .animation(.easeInOut(duration: 0.15), value: controller.stepIndex)
                .animation(.easeInOut(duration: 0.15), value: controller.isActive)
        }
    }
}
