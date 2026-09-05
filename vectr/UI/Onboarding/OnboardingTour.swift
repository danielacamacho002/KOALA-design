//
//  OnboardingTour.swift
//  vectr
//
//  Step models and static copy for the design and print-layout first-run tours.
//

import SwiftUI

/// UI element a tour step should call out. `.none` is a centered intro with no highlight.
enum OnboardingTarget: Equatable {
    case none
    case tool(ToolCategory)
    case commandPanel
    case layers
    case snaps
    case share
    case save
    case printLayout
    case modes
    case paperGrid
    case margins
    case printTool(PrintLayoutTool)
    case export
    case designChip

    /// Stable key for PreferenceKey dictionaries (avoids MainActor-isolated Hashable).
    var anchorID: String {
        switch self {
        case .none: return "none"
        case .commandPanel: return "commandPanel"
        case .layers: return "layers"
        case .snaps: return "snaps"
        case .share: return "share"
        case .save: return "save"
        case .printLayout: return "printLayout"
        case .modes: return "modes"
        case .paperGrid: return "paperGrid"
        case .margins: return "margins"
        case .export: return "export"
        case .designChip: return "designChip"
        case .tool(let category): return "tool.\(category.rawValue)"
        case .printTool(let tool): return "printTool.\(tool.rawValue)"
        }
    }
}

/// A single instructional hover-box step.
struct OnboardingStep: Identifiable, Equatable {
    let id: String
    let title: String
    let body: String
    let alignment: Alignment
    let padding: EdgeInsets
    let target: OnboardingTarget

    init(
        id: String,
        title: String,
        body: String,
        alignment: Alignment,
        padding: EdgeInsets,
        target: OnboardingTarget = .none
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.alignment = alignment
        self.padding = padding
        self.target = target
    }

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
                id: "design.intro",
                title: "Quick tutorial",
                body: "A short walk through the main controls. Tap Next to continue, or Skip all to dismiss.",
                alignment: .center,
                padding: EdgeInsets()
            ),
            designTool(
                .line,
                body: "Draw straight lines. Arc and construction variants live in the command panel."
            ),
            designTool(
                .circle,
                body: "Draw circles and ellipses from the center or the edge."
            ),
            designTool(
                .rectangle,
                body: "Draw rectangles from the center or a corner."
            ),
            designTool(
                .curve,
                body: "Sketch freehand or draw a curve on the canvas."
            ),
            designTool(
                .type,
                body: "Place and edit text on the canvas."
            ),
            OnboardingStep(
                id: "design.command",
                title: "Command panel",
                body: "The active-tool panel: pick variants, type points, and set thickness or color.",
                alignment: .topLeading,
                padding: EdgeInsets(top: 8, leading: 12, bottom: 0, trailing: 12),
                target: .commandPanel
            ),
            designTool(
                .move,
                body: "Select artwork, then move or rotate it."
            ),
            designTool(
                .scale,
                body: "Resize a selection — uniformly or freely."
            ),
            designTool(
                .dimensions,
                body: "Add measurement dimensions to your drawing."
            ),
            designTool(
                .trim,
                body: "Cut segments where paths meet."
            ),
            designTool(
                .fillet,
                body: "Round a corner between two edges."
            ),
            designTool(
                .addAnchor,
                body: "Insert points on a path."
            ),
            designTool(
                .pattern,
                body: "Repeat a selection in a pattern."
            ),
            designTool(
                .delete,
                body: "Remove selected artwork."
            ),
            OnboardingStep(
                id: "design.layers",
                title: "Layers",
                body: "Show, hide, lock, and reorder layers to keep artwork organized.",
                alignment: .topTrailing,
                padding: EdgeInsets(top: 56, leading: 12, bottom: 0, trailing: 12),
                target: .layers
            ),
            OnboardingStep(
                id: "design.snaps",
                title: "Snaps",
                body: "Toggle endpoint, midpoint, intersection, center, quadrant, and tangent snaps.",
                alignment: .bottomLeading,
                padding: EdgeInsets(top: 0, leading: 16, bottom: 64, trailing: 16),
                target: .snaps
            ),
            OnboardingStep(
                id: "design.share",
                title: "Share",
                body: "Export or share the design.",
                alignment: .topTrailing,
                padding: EdgeInsets(top: 8, leading: 12, bottom: 0, trailing: 12),
                target: .share
            ),
            OnboardingStep(
                id: "design.save",
                title: "Save",
                body: "Save the project.",
                alignment: .topTrailing,
                padding: EdgeInsets(top: 8, leading: 12, bottom: 0, trailing: 12),
                target: .save
            ),
            OnboardingStep(
                id: "design.printLayout",
                title: "Print Layout",
                body: "Open Print Layout to tile artwork across pages. A short tour starts the first time you go there.",
                alignment: .topTrailing,
                padding: EdgeInsets(top: 8, leading: 12, bottom: 0, trailing: 12),
                target: .printLayout
            ),
        ]
    )

    static let printLayout = OnboardingTour(
        id: "printLayout",
        steps: [
            OnboardingStep(
                id: "print.intro",
                title: "Quick tutorial",
                body: "A short walk through Print Layout. Tap Next to continue, or Skip all to dismiss.",
                alignment: .center,
                padding: EdgeInsets()
            ),
            OnboardingStep(
                id: "print.modes",
                title: "Modes",
                body: "Switch between Design and Print Layout from these chips.",
                alignment: .topLeading,
                padding: EdgeInsets(top: 8, leading: 12, bottom: 0, trailing: 12),
                target: .modes
            ),
            OnboardingStep(
                id: "print.paper",
                title: "Paper & grid",
                body: "Set the page size and how many columns and rows make up the print grid.",
                alignment: .topLeading,
                padding: EdgeInsets(top: 8, leading: 12, bottom: 0, trailing: 12),
                target: .paperGrid
            ),
            OnboardingStep(
                id: "print.margins",
                title: "Margins",
                body: "Choose the print border style and margin width on each page.",
                alignment: .topLeading,
                padding: EdgeInsets(top: 8, leading: 12, bottom: 0, trailing: 12),
                target: .margins
            ),
            OnboardingStep(
                id: "print.select",
                title: "Select",
                body: "Move and rotate artwork on the grid.",
                alignment: .topLeading,
                padding: EdgeInsets(top: 8, leading: 12, bottom: 0, trailing: 12),
                target: .printTool(.select)
            ),
            OnboardingStep(
                id: "print.cut",
                title: "Cut",
                body: "Split artwork across page borders.",
                alignment: .topLeading,
                padding: EdgeInsets(top: 8, leading: 12, bottom: 0, trailing: 12),
                target: .printTool(.cut)
            ),
            OnboardingStep(
                id: "print.export",
                title: "Export",
                body: "Export a tiled multi-page PDF.",
                alignment: .topTrailing,
                padding: EdgeInsets(top: 8, leading: 12, bottom: 0, trailing: 12),
                target: .export
            ),
            OnboardingStep(
                id: "print.back",
                title: "Back to Design",
                body: "Tap Design to return to the drawing editor.",
                alignment: .topLeading,
                padding: EdgeInsets(top: 8, leading: 12, bottom: 0, trailing: 12),
                target: .designChip
            ),
        ]
    )

    private static func designTool(_ category: ToolCategory, body: String) -> OnboardingStep {
        OnboardingStep(
            id: "design.\(category.rawValue)",
            title: category.label,
            body: body,
            alignment: .topLeading,
            padding: EdgeInsets(top: 8, leading: 12, bottom: 0, trailing: 12),
            target: .tool(category)
        )
    }
}

/// UserDefaults keys for first-run onboarding completion.
enum OnboardingSettings {
    static let designTourCompletedKey = "onboarding.designTourCompleted.v3"
    static let printTourCompletedKey = "onboarding.printTourCompleted.v2"
}
