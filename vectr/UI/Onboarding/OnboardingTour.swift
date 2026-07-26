//
//  OnboardingTour.swift
//  vectr
//
//  Step models and static copy for the design and print-layout first-run tours.
//

import SwiftUI

/// A single instructional hover-box step.
struct OnboardingStep: Identifiable, Equatable {
    let id: String
    let title: String
    let body: String
    let alignment: Alignment
    let padding: EdgeInsets

    static func == (lhs: OnboardingStep, rhs: OnboardingStep) -> Bool {
        lhs.id == rhs.id
    }
}

/// Ordered list of hover-box steps for one tour.
struct OnboardingTour: Equatable {
    let id: String
    let steps: [OnboardingStep]

    var stepCount: Int { steps.count }

    static let design = OnboardingTour(
        id: "design",
        steps: [
            OnboardingStep(
                id: "design.shapes",
                title: "Shape tools",
                body: "Line, Circle, Rectangle, Curve, and Type live in the top toolbar. Pick one to draw or place text on the canvas.",
                alignment: .topLeading,
                padding: EdgeInsets(top: 8, leading: 12, bottom: 0, trailing: 12)
            ),
            OnboardingStep(
                id: "design.command",
                title: "Command panel",
                body: "This sharp panel drives the active tool: pick a variant, type coordinates, and set thickness or color while you draw.",
                alignment: .topLeading,
                padding: EdgeInsets(top: 8, leading: 12, bottom: 0, trailing: 12)
            ),
            OnboardingStep(
                id: "design.edit",
                title: "Edit tools",
                body: "After the divider: Move, Scale, Dimensions, Trim, Fillet, Add Anchor, Pattern, and Delete for editing what you’ve drawn.",
                alignment: .topLeading,
                padding: EdgeInsets(top: 8, leading: 12, bottom: 0, trailing: 12)
            ),
            OnboardingStep(
                id: "design.project",
                title: "Project controls",
                body: "Undo, Redo, Settings, Print Layout, Share, and Save sit on the right side of the toolbar.",
                alignment: .topTrailing,
                padding: EdgeInsets(top: 8, leading: 12, bottom: 0, trailing: 12)
            ),
            OnboardingStep(
                id: "design.layers",
                title: "Layers",
                body: "The stack icon opens Layers. Toggle visibility, lock, rename, and reorder to keep artwork organized.",
                alignment: .topTrailing,
                padding: EdgeInsets(top: 56, leading: 12, bottom: 0, trailing: 12)
            ),
            OnboardingStep(
                id: "design.snaps",
                title: "Snaps",
                body: "Bottom-left toggles lock drawing to endpoints, midpoints, intersections, centers, quadrants, and tangents.",
                alignment: .bottomLeading,
                padding: EdgeInsets(top: 0, leading: 16, bottom: 64, trailing: 16)
            ),
            OnboardingStep(
                id: "design.printTeaser",
                title: "Print Layout",
                body: "Open Print Layout from the toolbar to tile artwork across pages. A short tour appears the first time you go there.",
                alignment: .topTrailing,
                padding: EdgeInsets(top: 8, leading: 12, bottom: 0, trailing: 12)
            ),
        ]
    )

    static let printLayout = OnboardingTour(
        id: "printLayout",
        steps: [
            OnboardingStep(
                id: "print.overview",
                title: "Print Layout",
                body: "Arrange your design on a multi-page paper grid, then export a tiled PDF ready to print.",
                alignment: .topLeading,
                padding: EdgeInsets(top: 8, leading: 12, bottom: 0, trailing: 12)
            ),
            OnboardingStep(
                id: "print.paper",
                title: "Paper & grid",
                body: "Use the document icon to set page size and how many columns and rows make up the print grid.",
                alignment: .topTrailing,
                padding: EdgeInsets(top: 8, leading: 12, bottom: 0, trailing: 12)
            ),
            OnboardingStep(
                id: "print.margins",
                title: "Margins",
                body: "The dashed-rectangle control sets the print border style and margin width on each page.",
                alignment: .topTrailing,
                padding: EdgeInsets(top: 8, leading: 12, bottom: 0, trailing: 12)
            ),
            OnboardingStep(
                id: "print.selectCut",
                title: "Select & Cut",
                body: "Select moves and rotates artwork on the grid. Cut taps near a page border to split artwork across pages.",
                alignment: .topLeading,
                padding: EdgeInsets(top: 8, leading: 12, bottom: 0, trailing: 12)
            ),
            OnboardingStep(
                id: "print.export",
                title: "Export",
                body: "Export builds a tiled multi-page PDF you can share or send to a printer.",
                alignment: .topTrailing,
                padding: EdgeInsets(top: 8, leading: 12, bottom: 0, trailing: 12)
            ),
            OnboardingStep(
                id: "print.back",
                title: "Back to Design",
                body: "Tap Design in the toolbar anytime to return to drawing.",
                alignment: .topLeading,
                padding: EdgeInsets(top: 8, leading: 12, bottom: 0, trailing: 12)
            ),
        ]
    )
}

/// UserDefaults keys for first-run onboarding completion.
enum OnboardingSettings {
    static let designTourCompletedKey = "onboarding.designTourCompleted"
    static let printTourCompletedKey = "onboarding.printTourCompleted"
}
