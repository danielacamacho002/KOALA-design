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
    var onSave: () -> Void
    var onSwitchToDesign: () -> Void
    var onExport: (PrintLayoutExportKind) -> Void
    var onChanged: () -> Void
    var onLayoutReady: (CGSize) -> Void
    var onFitToGrid: (CGSize) -> Void

    @State private var statusMessage: String?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.clear
                    .coordinateSpace(name: "printLayout")

                PrintLayoutCanvasView(
                    document: document,
                    printLayoutRevision: document.printLayoutRevision,
                    geometryRevision: document.geometryRevision,
                    onCanvasTap: handleCanvasTap
                )
                .ignoresSafeArea()

                PrintLayoutOverlayView(document: document, onChanged: onChanged)
                    .ignoresSafeArea()
                    .allowsHitTesting(document.printLayout.activeTool == .select)
            }
            .overlay(alignment: .bottomTrailing) {
                RecenterCanvasButton {
                    onFitToGrid(geometry.size)
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
            .onAppear {
                onLayoutReady(geometry.size)
            }
            .onChange(of: geometry.size) { _, size in
                onLayoutReady(size)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            PrintLayoutToolbarView(
                document: document,
                canUndo: canUndo,
                canRedo: canRedo,
                onBack: onBack,
                onUndo: onUndo,
                onRedo: onRedo,
                onSave: onSave,
                onSwitchToDesign: onSwitchToDesign,
                onExport: onExport,
                onSettingsChanged: onChanged
            )
        }
    }

    private func handleCanvasTap(at documentPoint: CGPoint) {
        switch document.printLayout.activeTool {
        case .select:
            let threshold = document.viewport.viewToDocument(distance: 16)
            _ = document.selectPrintElement(near: documentPoint, threshold: threshold)
            onChanged()
        case .printBorder:
            break
        case .cut:
            let threshold = document.viewport.viewToDocument(distance: 20)
            _ = document.cutAlongNearestPrintBorder(near: documentPoint, threshold: threshold)
            onChanged()
        }
    }
}
