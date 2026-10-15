import AppKit
import SwiftUI

/// A minimal single-line NSTextView wrapper -- NOT NSTextField. An
/// NSTextField's actual first responder while editing is its *field
/// editor*, a separate shared NSTextView instance, not the NSTextField
/// object itself -- so overriding paste(_:) on an NSTextField subclass is a
/// no-op; the field editor handles it, and its default implementation only
/// ever looks for string content. Owning the NSTextView directly sidesteps
/// that indirection entirely, which is what lets pasting a screenshot work.
///
/// Also force-grabs real first-responder status via
/// `window?.makeFirstResponder(_:)` once the panel is actually capable of
/// becoming key -- see KeyablePanel.
struct FocusableTextField: NSViewRepresentable {
    @Binding var text: String
    var autoFocus: Bool = false
    var onCommit: () -> Void = {}
    /// Called instead of the normal text paste when the pasteboard holds an
    /// image (e.g. a copied screenshot) at the moment Cmd+V is pressed.
    var onImagePaste: ((NSImage) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class PasteAwareTextView: NSTextView {
        var onImagePaste: ((NSImage) -> Void)?
        var onCommit: (() -> Void)?

        override func paste(_ sender: Any?) {
            if let image = NSImage(pasteboard: .general), let onImagePaste {
                onImagePaste(image)
                return
            }
            super.paste(sender)
        }

        // Single-line field: Return submits instead of inserting a newline.
        override func insertNewline(_ sender: Any?) {
            onCommit?()
        }
    }

    func makeNSView(context: Context) -> PasteAwareTextView {
        let textView = PasteAwareTextView()
        textView.string = text
        textView.isRichText = false
        textView.isFieldEditor = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = .systemFont(ofSize: 13)
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator
        textView.onImagePaste = onImagePaste
        textView.onCommit = onCommit
        if autoFocus {
            // The view isn't in a window yet on this same turn -- and even
            // once it is, the window itself may not be key yet immediately
            // after the panel opens, so keep retrying briefly rather than
            // giving up after one failed attempt.
            Self.grabFocus(textView, attemptsLeft: 10)
        }
        return textView
    }

    private static func grabFocus(_ view: NSView, attemptsLeft: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            guard let window = view.window else {
                if attemptsLeft > 0 { grabFocus(view, attemptsLeft: attemptsLeft - 1) }
                return
            }
            if window.firstResponder !== view {
                window.makeKey()
                let result = window.makeFirstResponder(view)
                if !result, attemptsLeft > 0 { grabFocus(view, attemptsLeft: attemptsLeft - 1) }
            }
        }
    }

    func updateNSView(_ nsView: PasteAwareTextView, context: Context) {
        context.coordinator.parent = self
        if nsView.string != text {
            nsView.string = text
        }
        nsView.onImagePaste = onImagePaste
        nsView.onCommit = onCommit
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: FocusableTextField
        init(_ parent: FocusableTextField) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}
