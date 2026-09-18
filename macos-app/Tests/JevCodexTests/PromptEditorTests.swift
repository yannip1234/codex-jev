import AppKit
import SwiftUI
import Testing
@testable import JevCodex

@MainActor private func returnEvent(_ flags: NSEvent.ModifierFlags = [], keypad: Bool = false) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                    timestamp: 0, windowNumber: 0, context: nil,
                    characters: keypad ? "\u{3}" : "\r", charactersIgnoringModifiers: keypad ? "\u{3}" : "\r",
                    isARepeat: false, keyCode: keypad ? 76 : 36)!
}

@Test @MainActor func promptEnterSubmitsWithoutAddingNewline() {
    _ = NSApplication.shared
    let editor = PromptTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 60))
    editor.string = "Hello"
    editor.canSubmit = true
    var submitted = 0
    editor.onSubmit = { submitted += 1 }
    editor.keyDown(with: returnEvent())
    editor.keyDown(with: returnEvent(keypad: true))
    #expect(submitted == 2)
    #expect(editor.string == "Hello")
}

@Test @MainActor func promptModifiedReturnAddsNewlines() {
    _ = NSApplication.shared
    let editor = PromptTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 60))
    editor.string = "Hello"
    editor.setSelectedRange(NSRange(location: 5, length: 0))
    editor.canSubmit = true
    var submitted = 0
    editor.onSubmit = { submitted += 1 }
    editor.keyDown(with: returnEvent(.shift))
    editor.keyDown(with: returnEvent(.option, keypad: true))
    #expect(submitted == 0)
    #expect(editor.string == "Hello\n\n")
}

@Test @MainActor func promptDisabledEnterDoesNotSubmitOrInsertNewline() {
    _ = NSApplication.shared
    let editor = PromptTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 60))
    editor.string = "Draft while running"
    var submitted = 0
    editor.onSubmit = { submitted += 1 }
    editor.keyDown(with: returnEvent())
    #expect(editor.performKeyEquivalent(with: returnEvent(.command)))
    #expect(submitted == 0)
    #expect(editor.string == "Draft while running")
}

@Test @MainActor func promptCommandReturnSubmitsThroughKeyEquivalent() {
    _ = NSApplication.shared
    let editor = PromptTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 60))
    editor.canSubmit = true
    var submitted = 0
    editor.onSubmit = { submitted += 1 }
    #expect(editor.performKeyEquivalent(with: returnEvent(.command)))
    #expect(submitted == 1)
}

@Test @MainActor func promptEnterDuringMarkedTextDoesNotSubmit() {
    _ = NSApplication.shared
    let editor = PromptTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 60))
    editor.canSubmit = true
    var submitted = 0
    editor.onSubmit = { submitted += 1 }
    editor.setMarkedText("composition", selectedRange: NSRange(location: 11, length: 0),
                         replacementRange: NSRange(location: NSNotFound, length: 0))
    #expect(editor.hasMarkedText())
    editor.keyDown(with: returnEvent())
    #expect(submitted == 0)
}

@Test @MainActor func promptBindingPreservesSelectionAndSynchronizesClear() {
    _ = NSApplication.shared
    var draft = "hello world"
    let binding = Binding(get: { draft }, set: { draft = $0 })
    let coordinator = PromptEditor(text: binding, canSubmit: true, onSubmit: {}).makeCoordinator()
    let editor = PromptTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 60))
    editor.string = draft
    editor.setSelectedRange(NSRange(location: 2, length: 3))
    coordinator.synchronize(editor)
    #expect(editor.selectedRange() == NSRange(location: 2, length: 3))
    editor.string = "updated draft"
    coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
    #expect(draft == "updated draft")
    draft = ""
    coordinator.synchronize(editor)
    #expect(editor.string.isEmpty)
    #expect(editor.selectedRange() == NSRange(location: 0, length: 0))
}

@Test @MainActor func promptExternalClearWaitsForComposition() {
    _ = NSApplication.shared
    var draft = "original"
    let binding = Binding(get: { draft }, set: { draft = $0 })
    let coordinator = PromptEditor(text: binding, canSubmit: true, onSubmit: {}).makeCoordinator()
    let editor = PromptTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 60))
    editor.string = draft
    editor.setMarkedText("composition", selectedRange: NSRange(location: 11, length: 0),
                         replacementRange: NSRange(location: 0, length: 8))
    draft = ""
    coordinator.synchronize(editor)
    #expect(editor.hasMarkedText())
    #expect(editor.string == "composition")
    editor.unmarkText()
    coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
    #expect(editor.string.isEmpty)
    #expect(draft.isEmpty)
}
