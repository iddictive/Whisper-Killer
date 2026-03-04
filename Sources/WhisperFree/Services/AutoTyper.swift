import Cocoa

final class AutoTyper {

    /// Inserts text into the active application using the selected method
    static func insert(text: String, method: InsertionMethod) {
        switch method {
        case .paste:
            simulatePaste()
        case .type:
            typeDirectly(text)
        }
    }

    /// Simulates Cmd+V to paste the current contents of the general pasteboard
    static func simulatePaste() {
        // Small delay to ensure the active application is ready after our overlay closes
        usleep(100_000) // 100ms

        // Simulate ⌘+V using CGEvent
        let source = CGEventSource(stateID: .combinedSessionState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // 'v' key
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cgAnnotatedSessionEventTap)
        keyUp?.post(tap: .cgAnnotatedSessionEventTap)
    }

    /// Directly "types" text into the focused application without using the clipboard
    static func typeDirectly(_ text: String) {
        guard !text.isEmpty else { return }
        
        // Small delay to ensure the active application is ready
        usleep(150_000) // Slightly increased to 150ms

        let source = CGEventSource(stateID: .combinedSessionState)
        
        // We inject the string using a single key down/up pair with a unicode string.
        // For very long strings, some apps might struggle, so we could chunk but for
        // typical voice dictation, this is much faster and more reliable than char-by-char.
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        
        let utf16Chars = Array(text.utf16)
        keyDown?.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)
        
        // Post events to the system session
        keyDown?.post(tap: .cgAnnotatedSessionEventTap)
        keyUp?.post(tap: .cgAnnotatedSessionEventTap)
    }
}

