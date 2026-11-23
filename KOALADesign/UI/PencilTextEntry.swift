//
//  PencilTextEntry.swift
//  Koala
//

import ObjectiveC
import UIKit

/// Apple Pencil may tap a text or number field to show the keyboard.
/// Scribble never inserts handwriting into those fields.
enum PencilTextEntry {
    private nonisolated(unsafe) static var didInstall = false

    static func install() {
        guard !didInstall else { return }
        didInstall = true
        swizzleDidMoveToWindow()
        swizzleAddInteraction()
    }

    static func suppressHandwriting(on view: UIView) {
        PencilTextEntryGate.install(on: view)
    }
}

/// Retained for the process lifetime. `UIScribbleInteraction.delegate` is weak.
private final class PencilTextEntryGate: NSObject, UIScribbleInteractionDelegate {
    static let shared = PencilTextEntryGate()

    func scribbleInteraction(_ interaction: UIScribbleInteraction, shouldBeginAt location: CGPoint) -> Bool {
        if let view = interaction.view,
           view.bounds.contains(location),
           Self.canFocus(view),
           !view.isFirstResponder {
            DispatchQueue.main.async {
                guard view.window != nil else { return }
                view.becomeFirstResponder()
            }
        }
        return false
    }

    func scribbleInteractionShouldDelayFocus(_ interaction: UIScribbleInteraction) -> Bool {
        false
    }

    static func install(on view: UIView) {
        guard view is UITextField || view is UITextView else { return }
        let foreign = view.interactions.compactMap { $0 as? UIScribbleInteraction }
            .filter { !($0.delegate is PencilTextEntryGate) }
        for interaction in foreign {
            view.removeInteraction(interaction)
        }
        let hasGate = view.interactions.contains {
            ($0 as? UIScribbleInteraction)?.delegate is PencilTextEntryGate
        }
        if !hasGate {
            view.addInteraction(UIScribbleInteraction(delegate: shared))
        }
    }

    private static func canFocus(_ view: UIView) -> Bool {
        guard view.isUserInteractionEnabled, !view.isHidden, view.alpha > 0.01 else { return false }
        if let field = view as? UITextField { return field.isEnabled }
        if let textView = view as? UITextView { return textView.isEditable }
        return false
    }
}

private nonisolated func swizzleDidMoveToWindow() {
    let selector = #selector(UIView.didMoveToWindow)
    guard let method = class_getInstanceMethod(UIView.self, selector) else { return }
    let originalIMP = method_getImplementation(method)
    let block: @convention(block) (AnyObject) -> Void = { object in
        let function = unsafeBitCast(
            originalIMP,
            to: (@convention(c) (AnyObject, Selector) -> Void).self
        )
        function(object, selector)
        MainActor.assumeIsolated {
            guard let view = object as? UIView else { return }
            PencilTextEntryGate.install(on: view)
        }
    }
    method_setImplementation(method, imp_implementationWithBlock(block))
}

private nonisolated func swizzleAddInteraction() {
    let selector = #selector(UIView.addInteraction(_:))
    guard let method = class_getInstanceMethod(UIView.self, selector) else { return }
    let originalIMP = method_getImplementation(method)
    let block: @convention(block) (AnyObject, AnyObject) -> Void = { object, interaction in
        let function = unsafeBitCast(
            originalIMP,
            to: (@convention(c) (AnyObject, Selector, AnyObject) -> Void).self
        )
        MainActor.assumeIsolated {
            guard let view = object as? UIView,
                  view is UITextField || view is UITextView,
                  let scribble = interaction as? UIScribbleInteraction,
                  !(scribble.delegate is PencilTextEntryGate) else {
                function(object, selector, interaction)
                return
            }
            let hasGate = view.interactions.contains {
                ($0 as? UIScribbleInteraction)?.delegate is PencilTextEntryGate
            }
            if !hasGate {
                function(view, selector, UIScribbleInteraction(delegate: PencilTextEntryGate.shared))
            }
        }
    }
    method_setImplementation(method, imp_implementationWithBlock(block))
}
