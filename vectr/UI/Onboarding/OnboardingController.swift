//
//  OnboardingController.swift
//  vectr
//
//  Drives a first-run tour: advance, skip all, and persist completion.
//

import Foundation
import Observation
import SwiftUI

@Observable
final class OnboardingController {
    let tour: OnboardingTour
    private(set) var stepIndex: Int = 0
    private(set) var isActive: Bool

    private let completedKey: String

    init(tour: OnboardingTour, completedKey: String) {
        self.tour = tour
        self.completedKey = completedKey
        self.isActive = !UserDefaults.standard.bool(forKey: completedKey)
    }

    var currentStep: OnboardingStep? {
        guard isActive, tour.steps.indices.contains(stepIndex) else { return nil }
        return tour.steps[stepIndex]
    }

    var currentTarget: OnboardingTarget? {
        currentStep?.target
    }

    var stepNumber: Int { stepIndex + 1 }

    var stepCount: Int { tour.stepCount }

    var isLastStep: Bool {
        stepIndex >= tour.stepCount - 1
    }

    var isFirstStep: Bool {
        stepIndex <= 0
    }

    func advance() {
        guard isActive else { return }
        withoutAnimation {
            if isLastStep {
                complete()
            } else {
                stepIndex += 1
            }
        }
    }

    func retreat() {
        guard isActive, !isFirstStep else { return }
        withoutAnimation {
            stepIndex -= 1
        }
    }

    func skipAll() {
        withoutAnimation {
            complete()
        }
    }

    /// Step changes should snap the instruction box. An animated move makes the
    /// Next button travel across the canvas.
    private func withoutAnimation(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }

    func restart() {
        UserDefaults.standard.set(false, forKey: completedKey)
        stepIndex = 0
        isActive = true
    }

    private func complete() {
        UserDefaults.standard.set(true, forKey: completedKey)
        isActive = false
    }
}
