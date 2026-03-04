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
        usleep(150_000) // 150ms

        let source = CGEventSource(stateID: .combinedSessionState)
        
        // Replace newlines with carriage returns. 
        // Many macOS apps treat \r as "newline without submitting" in text fields,
        // which helps avoid the "only first paragraph" or "premature send" issues.
        let correctedText = text.replacingOccurrences(of: "\n", with: "\r")
        
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        
        let utf16Chars = Array(correctedText.utf16)
        keyDown?.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)
        
        keyDown?.post(tap: .cgAnnotatedSessionEventTap)
        keyUp?.post(tap: .cgAnnotatedSessionEventTap)
    }
}

