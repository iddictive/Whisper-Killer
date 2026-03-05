import Cocoa
import Carbon

final class HotkeyManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var onKeyDown: (() -> Void)?
    private var onKeyUp: (() -> Void)?
    private var isKeyDown = false

    /// Current hotkey config — can be updated at runtime
    var config = HotkeyConfig()
    
    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Explicitly check trust including prompt if needed
    func checkTrust(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }


    deinit {
        stop()
    }

    func start(promptUser: Bool = false, onKeyDown: @escaping () -> Void, onKeyUp: @escaping () -> Void) {
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp

        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): promptUser] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            if promptUser {
                print("⚠️ Accessibility permission required for global hotkeys")
            }
            return
        }

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | 
                                    (1 << CGEventType.keyUp.rawValue) | 
                                    (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("❌ Failed to create event tap. Check accessibility permissions.")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isKeyDown = false // Reset state on stop
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable tap if system disabled it
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let pass = Unmanaged.passUnretained(event)

        // ── STATE A: No hotkey held ──────────────────────────────────
        if !isKeyDown {
            // Only care about keyDown of our exact hotkey — skip EVERYTHING else
            guard type == .keyDown else { return pass }
            let kc = Int(event.getIntegerValueField(.keyboardEventKeycode))
            guard kc == config.keyCode && checkModifiers(event.flags) else { return pass }

            // Hotkey pressed!
            isKeyDown = true
            DispatchQueue.main.async { [weak self] in self?.onKeyDown?() }
            return nil // swallow
        }

        // ── STATE B: Hotkey IS held (recording) ─────────────────────
        // We only care about TWO things:
        //   1. Our modifier released → fire onKeyUp
        //   2. Our key released       → fire onKeyUp

        if type == .flagsChanged {
            // Quick check: are OUR modifiers still held?
            // If yes (e.g. user pressed Cmd for Cmd-Tab but our Option is still down) → pass instantly
            if hotkeyModifiersStillHeld(event.flags) { return pass }
            // Our modifier was released
            isKeyDown = false
            DispatchQueue.main.async { [weak self] in self?.onKeyUp?() }
            return pass
        }

        if type == .keyUp {
            let kc = Int(event.getIntegerValueField(.keyboardEventKeycode))
            if kc == config.keyCode {
                isKeyDown = false
                DispatchQueue.main.async { [weak self] in self?.onKeyUp?() }
                return nil // swallow
            }
            return pass
        }

        if type == .keyDown {
            let kc = Int(event.getIntegerValueField(.keyboardEventKeycode))
            if kc == config.keyCode {
                return nil // swallow key-repeat
            }
            return pass
        }

        return pass
    }

    private func checkModifiers(_ flags: CGEventFlags) -> Bool {
        let needOption  = config.useOption
        let needCommand = config.useCommand
        let needControl = config.useControl
        let needShift   = config.useShift

        let hasOption  = flags.contains(.maskAlternate)
        let hasCommand = flags.contains(.maskCommand)
        let hasControl = flags.contains(.maskControl)
        let hasShift   = flags.contains(.maskShift)

        return (needOption == hasOption) &&
               (needCommand == hasCommand) &&
               (needControl == hasControl) &&
               (needShift == hasShift)
    }

    /// Checks ONLY the modifiers that the hotkey requires are still held.
    /// Unlike `checkModifiers` which requires an exact match, this ignores
    /// extra modifiers (e.g. Cmd pressed during Cmd-Tab won't cause a false release).
    private func hotkeyModifiersStillHeld(_ flags: CGEventFlags) -> Bool {
        if config.useOption  && !flags.contains(.maskAlternate) { return false }
        if config.useCommand && !flags.contains(.maskCommand)   { return false }
        if config.useControl && !flags.contains(.maskControl)   { return false }
        if config.useShift   && !flags.contains(.maskShift)     { return false }
        return true
    }
}
