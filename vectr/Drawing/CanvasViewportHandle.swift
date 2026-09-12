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

    func attach(_ view: DrawingCanvasUIView) {
        refreshImpl = { [weak view] in view?.refreshViewport() }
        animateImpl = { [weak view] target in view?.animateViewport(to: target) }
    }

    func attach(_ view: PrintLayoutCanvasUIView) {
        refreshImpl = { [weak view] in view?.refreshViewport() }
        animateImpl = { [weak view] target in
            view?.document.viewport = target
            view?.refreshViewport()
        }
    }

    func refreshViewport() {
        refreshImpl?()
    }

    func animateViewport(to target: ViewportTransform) {
        animateImpl?(target)
    }
}
