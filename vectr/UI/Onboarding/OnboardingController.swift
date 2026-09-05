//
//  OnboardingController.swift
//  vectr
//
//  Drives a first-run tour: advance, skip all, and persist completion.
//

import Foundation
import Observation

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

    func advance() {
        guard isActive else { return }
        if isLastStep {
            complete()
        } else {
            stepIndex += 1
        }
    }

    func skipAll() {
        complete()
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
