//
//  PrintLayoutView.swift
//  vectr
//

import SwiftUI

struct PrintLayoutView: View {
    @Bindable var document: VectrDocument
    var canUndo: Bool
    var canRedo: Bool
    var onBack: () -> Void
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onSwitchToDesign: () -> Void
    var onExport: () -> Void
    var onChanged: () -> Void
    var onLayoutReady: (CGRect) -> Void
    var onFitToGrid: (CGRect) -> Void
    var viewportHandle: CanvasViewportHandle

    @State private var statusMessage: String?
    @State private var showPaperPanel = false
    @State private var showMarginPanel = false
    @State private var printRotateMode = false
    @State private var printOnboarding = OnboardingController(
        tour: .printLayout,
        completedKey: OnboardingSettings.printTourCompletedKey
    )
    @State private var onboardingAnchors: [String: CGRect] = [:]
    @State private var onboardingOverlayFrame: CGRect = .zero
    @State private var printAxisLockEnabled = false

    /// Drives the move/rotate panel. The Cut tool leaves its fresh pieces selected,
    /// but the overlay handles are only live for Select, so the panel stays hidden
    /// until the tool can actually use it. The Select tour step opens it anyway so
    /// the instruction can sit beside the panel.
    private var hasPrintSelection: Bool {
        document.printLayout.activeTool == .select && !document.printSelectionIsEmpty
    }

    private var showsMovePanel: Bool {
        if printOnboarding.isActive, printOnboarding.currentTarget == .printTool(.select) {
            return true
        }
        return hasPrintSelection
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.clear
                    .coordinateSpace(name: "printLayout")

                PrintLayoutCanvasView(
                    document: document,
                    printLayoutRevision: document.printLayoutRevision,
                    geometryRevision: document.geometryRevision,
                    viewportHandle: viewportHandle,
                    onCanvasTap: handleCanvasTap
                )
                .ignoresSafeArea()
                .transaction { $0.animation = nil }

                PrintLayoutOverlayView(
                    document: document,
                    rotateModeActive: printRotateMode,
                    axisLockEnabled: printAxisLockEnabled,
                    onChanged: onChanged,
                    onSelectTap: {
                        showPaperPanel = false
                        showMarginPanel = false
                    }
                )
                .ignoresSafeArea()
                .allowsHitTesting(document.printLayout.activeTool == .select)
                .transaction { $0.animation = nil }

                ViewportNavigationInstaller(
                    document: document,
                    viewportHandle: viewportHandle,
                    onTwoFingerTap: onUndo
                )
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) {
                if showPaperPanel {
                    PrintPaperPanelView(
                        document: document,
                        units: document.settings.units,
                        onChanged: onChanged,
                        onClose: { showPaperPanel = false }
                    )
                    .transition(.identity)
                } else if showMarginPanel {
                    PrintMarginPanelView(
                        document: document,
                        units: document.settings.units,
                        onChanged: onChanged,
                        onClose: { showMarginPanel = false }
                    )
                    .transition(.identity)
                } else if showsMovePanel {
                    PrintMoveRotatePanelView(
                        document: document,
                        rotateModeActive: $printRotateMode,
                        axisLockEnabled: $printAxisLockEnabled,
                        onChanged: onChanged,
                        onClose: {
                            printRotateMode = false
                            document.clearPrintSelection()
                        }
                    )
                    .transition(.identity)
                }
            }
            .overlay(alignment: .topLeading) {
                if printOnboarding.currentStep?.target.boxPlacement == .besideCommandPanel,
                   let step = printOnboarding.currentStep {
                    OnboardingHoverBoxView(
                        step: step,
                        stepNumber: printOnboarding.stepNumber,
                        stepCount: printOnboarding.stepCount,
                        onNext: { printOnboarding.advance() },
                        onBack: { printOnboarding.retreat() },
                        onSkipAll: { printOnboarding.skipAll() },
                        canGoBack: !printOnboarding.isFirstStep
                    )
                    .id(step.id)
                    .padding(.leading, ToolPanelMetrics.commandWidth + 12)
                    .transition(.identity)
                    .transaction { $0.animation = nil }
                }
            }
            .onChange(of: document.printSelectedStrokeID) { _, _ in printRotateMode = false }
            .onChange(of: document.printSelectedTextID) { _, _ in printRotateMode = false }
            .onChange(of: document.printSelectionCount) { _, _ in printRotateMode = false }
            .overlay(alignment: .bottomTrailing) {
                RecenterCanvasButton {
                    onFitToGrid(geometry.frame(in: .global))
                }
                .padding(.trailing, 16)
                .padding(.bottom, 16)
            }
            .overlay(alignment: .bottom) {
                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 12)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                self.statusMessage = nil
                            }
                        }
                }
            }
            .onboardingTourOverlay(
                controller: printOnboarding,
                anchors: onboardingAnchors,
                overlayFrame: onboardingOverlayFrame
            )
            .onAppear {
                onLayoutReady(geometry.frame(in: .global))
            }
            .onChange(of: geometry.size) { _, _ in
                onLayoutReady(geometry.frame(in: .global))
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            PrintLayoutToolbarView(
                document: document,
                isPaperPanelOpen: $showPaperPanel,
                isMarginPanelOpen: $showMarginPanel,
                canUndo: canUndo,
                canRedo: canRedo,
                onBack: onBack,
                onUndo: onUndo,
                onRedo: onRedo,
                onSwitchToDesign: onSwitchToDesign,
                onExport: onExport,
                onSettingsChanged: onChanged,
                highlightedTarget: printOnboarding.currentTarget
            )
        }
        .onPreferenceChange(OnboardingAnchorPreferenceKey.self) { onboardingAnchors = $0 }
        .onPreferenceChange(OnboardingOverlayFrameKey.self) { onboardingOverlayFrame = $0 }
        .onChange(of: printOnboarding.stepIndex) { _, _ in
            syncPrintTourStep()
        }
        .onAppear {
            syncPrintTourStep()
        }
    }

    /// Opens the command panel for the current print-layout tour step and selects
    /// the matching tool. Other steps close those panels.
    private func syncPrintTourStep() {
        guard printOnboarding.isActive else { return }
        switch printOnboarding.currentTarget {
        case .paperGrid:
            showMarginPanel = false
            showPaperPanel = true
        case .margins:
            showPaperPanel = false
            showMarginPanel = true
        case .printTool(let tool):
            showPaperPanel = false
            showMarginPanel = false
            guard document.printLayout.activeTool != tool else { return }
            var settings = document.printLayout
            settings.activeTool = tool
            document.updatePrintLayout(settings, recordUndo: false)
        default:
            showPaperPanel = false
            showMarginPanel = false
        }
    }

    private func handleCanvasTap(at documentPoint: CGPoint) {
        if showPaperPanel { showPaperPanel = false }
        if showMarginPanel { showMarginPanel = false }
        switch document.printLayout.activeTool {
        case .select:
            break
        case .cut:
            let threshold = document.viewport.viewToDocument(distance: 20)
            _ = document.cutAlongNearestPrintBorder(near: documentPoint, threshold: threshold)
            onChanged()
        }
    }
}
