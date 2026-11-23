//
//  CanvasViewportHandle.swift
//  Koala
//

import CoreGraphics
import Foundation

/// Lets SwiftUI ask a UIKit canvas to move the camera without marking the
/// document dirty or rebuilding the editor.
@MainActor
final class CanvasViewportHandle {
    private var refreshImpl: (() -> Void)?
    private var animateImpl: ((ViewportTransform) -> Void)?
    private var cancelImpl: (() -> Void)?
    private var previewTranslationImpl: ((CGPoint, Set<UUID>, Set<UUID>) -> Void)?
    private var endTranslationPreviewImpl: ((Bool) -> Void)?
    private var gestureConsumedViewport = false

    func attach(_ view: DrawingCanvasUIView) {
        refreshImpl = { [weak view] in view?.refreshViewport() }
        animateImpl = { [weak view] target in view?.animateViewport(to: target) }
        cancelImpl = { [weak view] in view?.cancelViewportAnimation() }
        previewTranslationImpl = { [weak view] delta, strokeIDs, textIDs in
            view?.previewTranslation(delta: delta, strokeIDs: strokeIDs, textIDs: textIDs)
        }
        endTranslationPreviewImpl = { [weak view] reloadGeometry in
            view?.endTranslationPreview(reloadGeometry: reloadGeometry)
        }
    }

    func attach(_ view: PrintLayoutCanvasUIView) {
        refreshImpl = { [weak view] in view?.refreshViewport() }
        animateImpl = { [weak view] target in
            view?.document.viewport = target
            view?.refreshViewport()
        }
        cancelImpl = nil
        previewTranslationImpl = nil
        endTranslationPreviewImpl = nil
    }

    func refreshViewport() {
        refreshImpl?()
    }

    func animateViewport(to target: ViewportTransform) {
        animateImpl?(target)
    }

    func cancelViewportAnimation() {
        cancelImpl?()
    }

    /// Document-space preview of a group translation. Does not change the document.
    func previewTranslation(delta: CGPoint, strokeIDs: Set<UUID>, textIDs: Set<UUID>) {
        previewTranslationImpl?(delta, strokeIDs, textIDs)
    }

    /// Clears a translation preview. `reloadGeometry` rebuilds paths after a commit.
    func endTranslationPreview(reloadGeometry: Bool) {
        endTranslationPreviewImpl?(reloadGeometry)
    }

    func noteViewportGestureUpdate() {
        gestureConsumedViewport = true
    }

    func consumeViewportGestureUpdate() -> Bool {
        let consumed = gestureConsumedViewport
        gestureConsumedViewport = false
        return consumed
    }
}
