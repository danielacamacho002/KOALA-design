//
//  SingleTouchCanvasCatcher.swift
//  vectr
//
//  Full-canvas 1-finger pan + tap for the SwiftUI overlay. Capped at one touch
//  so a pinch can begin as soon as the second finger lands.
//

import SwiftUI
import UIKit

struct OverlayPointerValue {
    var startLocation: CGPoint
    var location: CGPoint
    var translation: CGSize
}

struct SingleTouchCanvasCatcher: UIViewRepresentable {
    var allowsDrag: Bool = true
    var onTap: ((CGPoint) -> Void)?
    var onDragChanged: ((OverlayPointerValue) -> Void)?
    var onDragEnded: ((OverlayPointerValue) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.coordinator = context.coordinator
        context.coordinator.view = view
        context.coordinator.bindRecognizers(on: view)
        configure(context.coordinator)
        return view
    }

    func updateUIView(_ uiView: CatcherView, context: Context) {
        uiView.coordinator = context.coordinator
        context.coordinator.view = uiView
        configure(context.coordinator)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: CatcherView, context: Context) -> CGSize {
        CGSize(width: proposal.width ?? uiView.bounds.width, height: proposal.height ?? uiView.bounds.height)
    }

    private func configure(_ coordinator: Coordinator) {
        coordinator.allowsDrag = allowsDrag
        coordinator.onTap = onTap
        coordinator.onDragChanged = onDragChanged
        coordinator.onDragEnded = onDragEnded
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var allowsDrag = true
        var onTap: ((CGPoint) -> Void)?
        var onDragChanged: ((OverlayPointerValue) -> Void)?
        var onDragEnded: ((OverlayPointerValue) -> Void)?
        weak var view: CatcherView?

        private var didBind = false

        func bindRecognizers(on view: CatcherView) {
            guard !didBind else { return }
            didBind = true
            view.pan.addTarget(self, action: #selector(handlePan(_:)))
            view.pan.delegate = self
            view.tap.addTarget(self, action: #selector(handleTap(_:)))
            view.tap.delegate = self
            view.tap.require(toFail: view.pan)
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let view, gestureRecognizer === view.pan else { return true }
            guard allowsDrag else { return false }
            let translation = view.pan.translation(in: view)
            return hypot(translation.x, translation.y) >= 2
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            // Let ancestor pinch / two-finger pan run; this pan fails on a
            // second finger because maximumNumberOfTouches is 1.
            true
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            switch gesture.state {
            case .began, .changed:
                onDragChanged?(pointerValue(from: gesture, in: view))
            case .ended, .cancelled:
                onDragEnded?(pointerValue(from: gesture, in: view))
            default:
                break
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let view = gesture.view else { return }
            onTap?(gesture.location(in: view))
        }

        private func pointerValue(from gesture: UIPanGestureRecognizer, in view: UIView) -> OverlayPointerValue {
            let location = gesture.location(in: view)
            let translation = gesture.translation(in: view)
            return OverlayPointerValue(
                startLocation: CGPoint(x: location.x - translation.x, y: location.y - translation.y),
                location: location,
                translation: CGSize(width: translation.x, height: translation.y)
            )
        }
    }

    final class CatcherView: UIView {
        let pan = UIPanGestureRecognizer()
        let tap = UITapGestureRecognizer()
        weak var coordinator: Coordinator?

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isMultipleTouchEnabled = true
            pan.minimumNumberOfTouches = 1
            pan.maximumNumberOfTouches = 1
            pan.cancelsTouchesInView = false
            tap.numberOfTouchesRequired = 1
            tap.cancelsTouchesInView = false
            addGestureRecognizer(pan)
            addGestureRecognizer(tap)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

    }
}
