import AppKit
import SwiftUI

struct PromptEditor: NSViewRepresentable {
    @Binding var text: String
    let canSubmit: Bool
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        let editor = PromptTextView(frame: scrollView.bounds)
        editor.isRichText = false
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.font = .systemFont(ofSize: 15)
        editor.textColor = .labelColor
        editor.textContainerInset = .zero
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width,
                                                     height: .greatestFiniteMagnitude)
        editor.setAccessibilityLabel("Message")
        editor.string = text
        editor.delegate = context.coordinator
        editor.canSubmit = canSubmit
        editor.onSubmit = onSubmit
        scrollView.documentView = editor
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let editor = scrollView.documentView as? PromptTextView else { return }
        context.coordinator.parent = self
        editor.canSubmit = canSubmit
        editor.onSubmit = onSubmit
        context.coordinator.synchronize(editor)
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PromptEditor
        private var lastBindingText: String
        private var pendingExternalText: String?

        init(_ parent: PromptEditor) {
            self.parent = parent
            lastBindingText = parent.text
        }

        func synchronize(_ editor: NSTextView) {
            if parent.text != lastBindingText {
                pendingExternalText = parent.text
                lastBindingText = parent.text
            }
            guard !editor.hasMarkedText(), let replacement = pendingExternalText else { return }
            pendingExternalText = nil
            guard editor.string != replacement else { return }
            let selection = editor.selectedRange()
            editor.string = replacement
            let length = (replacement as NSString).length
            let location = min(selection.location, length)
            editor.setSelectedRange(NSRange(location: location, length: min(selection.length, length - location)))
        }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            if pendingExternalText != nil {
                synchronize(editor)
                return
            }
            lastBindingText = editor.string
            parent.text = editor.string
        }
    }
}

class PromptTextView: NSTextView {
    var canSubmit = false
    var onSubmit: () -> Void = {}

    override func keyDown(with event: NSEvent) {
        guard handleReturn(event) else {
            super.keyDown(with: event)
            return
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), handleReturn(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    private func handleReturn(_ event: NSEvent) -> Bool {
        guard event.keyCode == 36 || event.keyCode == 76, !hasMarkedText() else { return false }
        if event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.option) {
            insertNewline(nil)
        } else if canSubmit {
            onSubmit()
        }
        // Consume disabled sends too: Return must never activate the Stop button.
        return true
    }
}
