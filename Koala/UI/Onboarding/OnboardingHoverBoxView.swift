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

    private let panelWidth: CGFloat = 360
    private let demoHeight: CGFloat = 128

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(step.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)

            if let demo = OnboardingDemo.demo(for: step) {
                OnboardingDemoView(demo: demo)
                    .frame(maxWidth: .infinity)
                    .frame(height: demoHeight)
                    .overlay(Rectangle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                    .accessibilityHidden(true)
            }

            Text(step.body)
                .font(.system(size: 15))
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(4)

            Text("\(stepNumber) / \(stepCount)")
                .font(.caption)
                .foregroundStyle(Color.toolPanelSecondaryLabel)

            HStack(spacing: 8) {
                ToolPanelLabelButton(title: "Skip all", action: onSkipAll)
                Spacer(minLength: 0)
                ToolPanelLabelButton(title: "Back", isDisabled: !canGoBack, action: onBack)
                ToolPanelLabelButton(title: "Next", action: onNext)
            }
        }
        .toolPanelChrome(width: panelWidth)
        .overlay {
            if step.target == .none {
                Rectangle()
                    .strokeBorder(.white.opacity(0.35), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(step.title), step \(stepNumber) of \(stepCount)")
    }
}

/// Pins the instruction card near the top of the canvas so the area below
/// stays open for drawing while the tour is visible.
struct OnboardingTourOverlay: View {
    var controller: OnboardingController
    var overlayFrame: CGRect

    var body: some View {
        if controller.isActive, let step = controller.currentStep {
            OnboardingHoverBoxView(
                step: step,
                stepNumber: controller.stepNumber,
                stepCount: controller.stepCount,
                onNext: { controller.advance() },
                onBack: { controller.retreat() },
                onSkipAll: { controller.skipAll() },
                canGoBack: !controller.isFirstStep
            )
            .offset(x: horizontalWindowOffset)
            .id(step.id)
            .transition(.identity)
            .transaction { $0.animation = nil }
        }
    }

    /// The overlay is the canvas. Shift horizontally when that canvas is not
    /// centered in the window so the card stays in the middle of the screen.
    private var horizontalWindowOffset: CGFloat {
        guard overlayFrame.width > 0, overlayFrame.height > 0,
              let window = Self.keyWindow
        else { return 0 }

        let windowOnScreen = window.convert(window.bounds, to: window.screen.coordinateSpace)
        let overlayCenter = CGPoint(x: overlayFrame.midX, y: overlayFrame.midY)
        let screenFrame = windowOnScreen.contains(overlayCenter) ? windowOnScreen : window.bounds
        return screenFrame.midX - overlayCenter.x
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
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
    /// Hosts the onboarding hover box just below the toolbar, leaving the
    /// canvas underneath free to draw on.
    func onboardingTourOverlay(
        controller: OnboardingController,
        overlayFrame: CGRect = .zero
    ) -> some View {
        overlay(alignment: .top) {
            OnboardingTourOverlay(
                controller: controller,
                overlayFrame: overlayFrame
            )
            .padding(.top, 16)
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
                OnboardingPulseRing(cornerRadius: cornerRadius, color: color)
            }
        }
    }
}

/// Highlight ring whose opacity eases on its own clock. Step changes disable
/// SwiftUI animation so the card snaps; this pulse must not use that transaction.
private struct OnboardingPulseRing: View {
    var cornerRadius: CGFloat
    var color: Color

    private let period: TimeInterval = 1.1

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
            let wave = pulseWave(at: context.date)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(color.opacity(0.45 + 0.55 * wave), lineWidth: 2)
        }
    }

    private func pulseWave(at date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate
        return 0.5 + 0.5 * sin(t * .pi * 2 / period)
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
