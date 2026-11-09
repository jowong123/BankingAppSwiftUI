import SwiftUI
import UIKit.UIGestureRecognizerSubclass

/// Tells the app about every touch anywhere in the window, for the inactivity auto-lock.
///
/// A UIKit wrapper (CLAUDE.md allows UIKit only behind wrappers): SwiftUI has no way to
/// observe all touches, including scrolls. The recognizer watches and never interferes:
/// it fails on the first touch, and doesn't cancel or delay touches for anything else.
struct ActivityMonitor: UIViewRepresentable {
    let onActivity: @MainActor () -> Void

    func makeUIView(context: Context) -> WindowHookView {
        WindowHookView(onActivity: onActivity)
    }

    func updateUIView(_ view: WindowHookView, context: Context) {
        view.recorder.onTouch = onActivity
    }
}

/// An invisible view whose only job is to attach the recorder to its window.
final class WindowHookView: UIView {
    let recorder: TouchRecorder

    init(onActivity: @escaping @MainActor () -> Void) {
        recorder = TouchRecorder(onTouch: onActivity)
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        recorder.view?.removeGestureRecognizer(recorder)
        window?.addGestureRecognizer(recorder)
    }
}

final class TouchRecorder: UIGestureRecognizer {
    var onTouch: @MainActor () -> Void

    init(onTouch: @escaping @MainActor () -> Void) {
        self.onTouch = onTouch
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        onTouch()
        state = .failed
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }
}
