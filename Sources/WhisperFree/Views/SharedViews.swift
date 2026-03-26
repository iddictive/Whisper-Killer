import SwiftUI

// MARK: - Generic UI Components

struct ExampleBox: View {
    let title: String
    let text: String
    let icon: String
    var isOutput: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(isOutput ? SW.accentBlue : SW.text3)
            
            Text(text)
                .font(.system(size: 12, weight: .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .foregroundStyle(.primary)
        }
    }
}

struct TextEditorCustom: View {
    @Binding var text: String
    let placeholder: String
    var isMonospaced: Bool = false
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(isMonospaced ? .system(size: 12, design: .monospaced) : .system(size: 11))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
            }
            
            TextEditor(text: $text)
                .font(isMonospaced ? .system(size: 12, design: .monospaced) : .system(size: 11))
                .scrollContentBackground(.hidden)
                .background(.clear)
                .padding(4)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}

struct WindowHeaderUnderlay: View {
    var body: some View {
        VisualEffectView(material: .sidebar, blendingMode: .withinWindow)
            .overlay(alignment: .bottom) {
                Divider()
                    .opacity(0.08)
            }
            .frame(height: 32)
            .accessibilityHidden(true)
    }
}

// MARK: - Hotkey Input Handling

struct KeyEventHandlingView: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var modifierFlags: CGEventFlags
    var onCommit: (Int, Bool, Bool, Bool, Bool) -> Void

    func makeNSView(context: Context) -> KeyView {
        let view = KeyView()
        view.onFlagsChanged = { flags in
            DispatchQueue.main.async {
                self.modifierFlags = flags
            }
        }
        view.onKeyDown = { keyCode, flags in
            DispatchQueue.main.async {
                let useOpt = flags.contains(.maskAlternate)
                let useCmd = flags.contains(.maskCommand)
                let useCtrl = flags.contains(.maskControl)
                let useShift = flags.contains(.maskShift)
                
                self.onCommit(keyCode, useOpt, useCmd, useCtrl, useShift)
            }
        }
        return view
    }

    func updateNSView(_ nsView: KeyView, context: Context) {
        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    class KeyView: NSView {
        var onFlagsChanged: ((CGEventFlags) -> Void)?
        var onKeyDown: ((Int, CGEventFlags) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func flagsChanged(with event: NSEvent) {
            onFlagsChanged?(CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)))
            super.flagsChanged(with: event)
        }

        override func keyDown(with event: NSEvent) {
            let kc = Int(event.keyCode)
            
            // Ignore pure modifier presses
            let modifierKeyCodes = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
            if modifierKeyCodes.contains(kc) {
                return
            }
            
            onKeyDown?(kc, CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)))
        }
    }
}
