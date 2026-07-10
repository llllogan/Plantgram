import SwiftUI
import UIKit

private struct KeyboardDismissModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(WindowKeyboardDismissView())
    }
}

extension View {
    func dismissKeyboardOnTap() -> some View {
        modifier(KeyboardDismissModifier())
    }
}

private struct WindowKeyboardDismissView: UIViewRepresentable {
    func makeUIView(context: Context) -> KeyboardDismissView {
        KeyboardDismissView()
    }

    func updateUIView(_ uiView: KeyboardDismissView, context: Context) {}
}

private final class KeyboardDismissView: UIView, UIGestureRecognizerDelegate {
    private lazy var tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
    private weak var attachedWindow: UIWindow?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        tapGesture.cancelsTouchesInView = false
        tapGesture.delaysTouchesBegan = false
        tapGesture.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()

        if attachedWindow !== window {
            attachedWindow?.removeGestureRecognizer(tapGesture)
            attachedWindow = window
        }

        window?.addGestureRecognizer(tapGesture)
    }

    @objc private func dismissKeyboard() {
        window?.endEditing(true)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var touchedView = touch.view
        while let view = touchedView {
            if view is UITextField || view is UITextView {
                return false
            }
            touchedView = view.superview
        }
        return true
    }

    deinit {
        attachedWindow?.removeGestureRecognizer(tapGesture)
    }
}
