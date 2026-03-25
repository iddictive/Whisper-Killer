import SwiftUI
import AppKit

// MARK: - Subtitle Overlay Content

struct SubtitleOverlayContent: View {
    @ObservedObject var manager = LiveTranslatorManager.shared
    
    private var compactMode: Bool {
        Storage.shared.loadSettings().liveTranslatorCompactMode
    }
    
    var body: some View {
        ZStack {
            if !manager.originalText.isEmpty || !manager.translatedText.isEmpty || manager.statusMessage != nil {
                VStack(spacing: compactMode ? 4 : 8) {
                    HStack(spacing: 12) {
                        // Language & Compact Toggle
                        HStack(spacing: 8) {
                            Menu {
                                ForEach(AppSettings.supportedLanguages, id: \.code) { lang in
                                    Button(lang.name) {
                                        Storage.shared.updateSettings { $0.liveTranslatorTargetLanguage = lang.name }
                                        NotificationCenter.default.post(name: NSNotification.Name("LiveTranslatorSettingsChanged"), object: nil)
                                    }
                                }
                            } label: {
                                Text(Storage.shared.loadSettings().liveTranslatorTargetLanguage)
                                    .font(.system(size: compactMode ? 10 : 12, weight: .bold))
                                    .foregroundColor(.accentColor)
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            
                            Divider().frame(height: 10)
                            
                            // Compact Toggle Icon
                            Button(action: {
                                Storage.shared.updateSettings { $0.liveTranslatorCompactMode.toggle() }
                            }) {
                                Image(systemName: compactMode ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
                                    .font(.system(size: 10))
                                    .foregroundColor(compactMode ? Color.accentColor : Color.white.opacity(0.4))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.05))
                        .clipShape(Capsule())
                        
                        Spacer()
                        
                        // Drag Handle
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.3))
                        
                        Spacer()
                        
                        // Close
                        Button(action: { manager.stop() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.2))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, compactMode ? 0 : 4)
                    
                    // Original Text (Hidden in super compact or if empty)
                    if !manager.originalText.isEmpty && !compactMode {
                        Text(manager.originalText)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .animation(.none, value: manager.originalText)
                            .padding(.horizontal, 4)
                    }
                    
                    // Translated Text
                    if !manager.translatedText.isEmpty {
                        Text(manager.translatedText)
                            .font(.system(size: compactMode ? 22 : 30, weight: .bold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(compactMode ? 3 : 5)
                            .animation(.none, value: manager.translatedText)
                    } else if let status = manager.statusMessage {
                        Text(status)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.accentColor)
                    }
                }
                .padding(.horizontal, compactMode ? 16 : 24)
                .padding(.vertical, compactMode ? 10 : 16)
                .frame(minWidth: compactMode ? 200 : 300, maxWidth: compactMode ? 500 : 800)
                .background(
                    ZStack {
                        VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                            .clipShape(RoundedRectangle(cornerRadius: compactMode ? 16 : 24))
                        
                        RoundedRectangle(cornerRadius: compactMode ? 16 : 24)
                            .fill(Color.black.opacity(0.4))
                        
                        RoundedRectangle(cornerRadius: compactMode ? 16 : 24)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    }
                )
                .shadow(color: .black.opacity(0.4), radius: 25, y: 12)
                .contentShape(RoundedRectangle(cornerRadius: compactMode ? 16 : 24))
                .padding(60) // Increased padding to prevent any shadow clipping
                .background(
                    GeometryReader { geo in
                        Color.clear.onAppear {
                            SubtitleOverlayController.shared.updateWindowSize(geo.size)
                        }
                        .onChange(of: geo.size) { _, newSize in
                            SubtitleOverlayController.shared.updateWindowSize(newSize)
                        }
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Ghost Panel for Subtitles

private class SubtitlePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Subtitle Overlay Controller

@MainActor
final class SubtitleOverlayController: NSObject, ObservableObject {
    static let shared = SubtitleOverlayController()
    private var panel: NSPanel?

    func show() {
        if panel == nil {
            let content = SubtitleOverlayContent()

            let hostingView = NSHostingView(rootView: content)
            hostingView.translatesAutoresizingMaskIntoConstraints = false

            guard let screen = NSScreen.main else { return }
            
            // Make it wide but not full width, positioned at the bottom
            // Increase panel size to accommodate shadow and padding
            let panelWidth: CGFloat = 1000
            let panelHeight: CGFloat = 400
            let x = screen.frame.midX - (panelWidth / 2)
            let y = screen.visibleFrame.minY + 20 

            let newPanel = SubtitlePanel(
                contentRect: NSRect(x: x, y: y, width: panelWidth, height: panelHeight),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            
            newPanel.isFloatingPanel = true
            newPanel.level = .popUpMenu // Or .screenSaver to be above almost everything
            newPanel.backgroundColor = .clear
            newPanel.isOpaque = false
            newPanel.hasShadow = false
            newPanel.animationBehavior = .none
            newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            newPanel.isMovableByWindowBackground = true
            newPanel.hidesOnDeactivate = false
            newPanel.ignoresMouseEvents = false

            newPanel.contentView = hostingView
            self.panel = newPanel
            
            // Fix: Initial behavior - clicks should only hit the content, not empty parts of the panel
            // but for simple movement, we'll keep the whole panel sized to content if possible
            
            // Add observer for LiveTranslatorManager stopping to auto-hide
            NotificationCenter.default.addObserver(self, selector: #selector(hideIfStopped), name: NSNotification.Name("LiveTranslatorStopped"), object: nil)
        }
        
        panel?.orderFrontRegardless() // Ensure it goes to front
    }


    func updateWindowSize(_ size: CGSize) {
        guard let panel = panel else { return }
        
        // Center horizontally at bottom
        guard let screen = NSScreen.main else { return }
        
        let x = screen.frame.midX - (size.width / 2)
        let y = screen.visibleFrame.minY + 20
        
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true, animate: false)
    }
    
    func hide() {
        panel?.orderOut(nil)
    }

    @objc private func hideIfStopped() {
        hide()
    }
}
