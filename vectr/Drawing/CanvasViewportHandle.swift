//
//  CanvasViewportHandle.swift
//  vectr
//

import Foundation

/// Lets SwiftUI ask a UIKit canvas to move the camera without marking the
/// document dirty or rebuilding the editor.
@MainActor
final class CanvasViewportHandle {
    private var refreshImpl: (() -> Void)?
    private var animateImpl: ((ViewportTransform) -> Void)?
    private var cancelImpl: (() -> Void)?
    private var gestureConsumedViewport = false

    func attach(_ view: DrawingCanvasUIView) {
        refreshImpl = { [weak view] in view?.refreshViewport() }
        animateImpl = { [weak view] target in view?.animateViewport(to: target) }
        cancelImpl = { [weak view] in view?.cancelViewportAnimation() }
    }

    func attach(_ view: PrintLayoutCanvasUIView) {
        refreshImpl = { [weak view] in view?.refreshViewport() }
        animateImpl = { [weak view] target in
            view?.document.viewport = target
            view?.refreshViewport()
        }
        cancelImpl = nil
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

    func noteViewportGestureUpdate() {
        gestureConsumedViewport = true
    }

    func consumeViewportGestureUpdate() -> Bool {
        let consumed = gestureConsumedViewport
        gestureConsumedViewport = false
        return consumed
    }
}
