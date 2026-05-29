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

enum APIKeyFieldPresentation {
    case roundedBorder
    case setupCard
}

struct MaskedAPIKeyField: View {
    @Binding var apiKey: String
    let presentation: APIKeyFieldPresentation
    let onChanged: () -> Void
    @State private var isEditing = false

    private var normalizedKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var shouldShowMaskedValue: Bool {
        !normalizedKey.isEmpty && !isEditing
    }

    var body: some View {
        HStack(spacing: 8) {
            fieldContent

            if !normalizedKey.isEmpty {
                Button {
                    isEditing.toggle()
                } label: {
                    Image(systemName: isEditing ? "eye.slash" : "pencil")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .help(isEditing
                    ? L.tr("Hide API key", "Скрыть API key")
                    : L.tr("Edit API key", "Изменить API key")
                )
            }
        }
    }

    @ViewBuilder
    private var fieldContent: some View {
        if shouldShowMaskedValue {
            Text(maskedKey(normalizedKey))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    isEditing = true
                }
                .modifier(APIKeyFieldPresentationModifier(presentation: presentation))
        } else {
            SecureField("sk-...", text: $apiKey)
                .onChange(of: apiKey) { _, _ in
                    isEditing = true
                    onChanged()
                }
                .modifier(APIKeyFieldPresentationModifier(presentation: presentation))
        }
    }

    private func maskedKey(_ key: String) -> String {
        let suffixLength = min(4, key.count)
        let suffix = String(key.suffix(suffixLength))

        if key.hasPrefix("sk-") {
            return "sk-...\(suffix)"
        }

        let prefix = String(key.prefix(min(3, key.count)))
        return "\(prefix)...\(suffix)"
    }
}

private struct APIKeyFieldPresentationModifier: ViewModifier {
    let presentation: APIKeyFieldPresentation

    func body(content: Content) -> some View {
        switch presentation {
        case .roundedBorder:
            content
                .textFieldStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                )
        case .setupCard:
            content
                .textFieldStyle(.plain)
                .padding(10)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
        }
    }
}

struct WindowHeaderUnderlay: View {
    var height: CGFloat = 0

    var body: some View {
        VisualEffectView(material: .sidebar, blendingMode: .withinWindow)
            .frame(height: height)
            .overlay(alignment: .bottom) {
                if height > 0 {
                    Divider()
                        .opacity(0.08)
                }
            }
            .accessibilityHidden(true)
    }
}

struct ClickableDisclosure<Label: View, Content: View>: View {
    @Binding var isExpanded: Bool
    let label: Label
    let content: Content

    init(
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self._isExpanded = isExpanded
        self.content = content()
        self.label = label()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    label
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                content
            }
        }
    }
}

struct NonDraggableContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            NonDraggableRepresentable()
            content
        }
    }
}

private struct NonDraggableRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        NonDraggableNSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class NonDraggableNSView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
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
