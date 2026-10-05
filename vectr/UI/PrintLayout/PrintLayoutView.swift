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
    /// until the tool can actually use it.
    private var hasPrintSelection: Bool {
        document.printLayout.activeTool == .select && !document.printSelectionIsEmpty
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
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                } else if showMarginPanel {
                    PrintMarginPanelView(
                        document: document,
                        units: document.settings.units,
                        onChanged: onChanged,
                        onClose: { showMarginPanel = false }
                    )
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                } else if hasPrintSelection {
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
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .animation(.easeInOut(duration: 0.15), value: showPaperPanel)
            .animation(.easeInOut(duration: 0.15), value: showMarginPanel)
            .animation(.easeInOut(duration: 0.15), value: hasPrintSelection)
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
