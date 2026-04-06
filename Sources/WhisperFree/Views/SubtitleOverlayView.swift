import SwiftUI
import AppKit

struct SubtitleOverlayContent: View {
    @ObservedObject var manager = LiveTranslatorManager.shared

    private var compactMode: Bool {
        Storage.shared.loadSettings().liveTranslatorCompactMode
    }

    private var targetLanguageLabel: String {
        AppSettings.normalizedLiveTranslatorTargetLanguage(Storage.shared.loadSettings().liveTranslatorTargetLanguage)
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                Spacer(minLength: 0)

                TranscriptDockView(
                    manager: manager,
                    compactMode: compactMode,
                    targetLanguageLabel: targetLanguageLabel,
                    containerSize: geo.size
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            SubtitleOverlayController.shared.updateWindowSize(proxy.size)
                        }
                        .onChange(of: proxy.size) { _, newSize in
                            SubtitleOverlayController.shared.updateWindowSize(newSize)
                        }
                }
            )
        }
    }
}

private struct TranscriptDockView: View {
    @ObservedObject var manager: LiveTranslatorManager
    let compactMode: Bool
    let targetLanguageLabel: String
    let containerSize: CGSize

    private var panelWidth: CGFloat {
        let preferred = containerSize.width * 0.34
        return min(max(preferred, 460), 720)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TranscriptDockHeader(
                compactMode: compactMode,
                targetLanguageLabel: targetLanguageLabel,
                statusMessage: manager.statusMessage
            )

            Divider()
                .overlay(Color.white.opacity(0.08))

            TranscriptColumnHeader(targetLanguageLabel: targetLanguageLabel)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()
                .overlay(Color.white.opacity(0.06))

            TranscriptSegmentsView(
                segments: manager.transcriptSegments,
                originalText: manager.originalText,
                translatedText: manager.translatedText,
                compactMode: compactMode
            )
        }
        .frame(width: panelWidth, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.56),
                        Color(red: 0.11, green: 0.10, blue: 0.10).opacity(0.48)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RoundedRectangle(cornerRadius: 0)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.top, 18)
        .padding(.trailing, 18)
        .padding(.bottom, 18)
        .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
    }
}

private struct TranscriptDockHeader: View {
    let compactMode: Bool
    let targetLanguageLabel: String
    let statusMessage: String?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(compactMode ? L.tr("Call Feed", "Лента звонка") : L.tr("Live Call Transcript", "Живая стенограмма звонка"))
                    .font(.system(size: compactMode ? 12 : 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))

                Menu {
                    ForEach(AppSettings.supportedLanguages, id: \.code) { lang in
                        Button(lang.name) {
                            Storage.shared.updateSettings { $0.liveTranslatorTargetLanguage = lang.name }
                            NotificationCenter.default.post(name: NSNotification.Name("LiveTranslatorSettingsChanged"), object: nil)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "globe")
                            .font(.system(size: 10, weight: .semibold))
                        Text(targetLanguageLabel)
                            .font(.system(size: 12, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Spacer(minLength: 8)

            if let statusMessage {
                OverlayStatusChip(
                    text: statusMessage,
                    icon: "dot.radiowaves.left.and.right",
                    isAccent: true
                )
            }

            Button(action: {
                Storage.shared.updateSettings { $0.liveTranslatorCompactMode.toggle() }
            }) {
                Image(systemName: compactMode ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(compactMode ? Color.accentColor : Color.white.opacity(0.78))
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)

            Button(action: { LiveTranslatorManager.shared.stop() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct TranscriptColumnHeader: View {
    let targetLanguageLabel: String

    var body: some View {
        HStack(spacing: 12) {
            TranscriptHeaderBadge(title: "Original")
            TranscriptHeaderBadge(title: targetLanguageLabel)
        }
    }
}

private struct TranscriptHeaderBadge: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.45))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TranscriptSegmentsView: View {
    let segments: [LiveTranscriptSegment]
    let originalText: String
    let translatedText: String
    let compactMode: Bool

    private var shouldShowDraft: Bool {
        !originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        segments.last?.originalText != originalText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if segments.isEmpty && !shouldShowDraft {
                    OverlayEmptyTranscriptState()
                        .padding(16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(segments) { segment in
                            TranscriptSegmentRow(segment: segment, compactMode: compactMode)
                                .id(segment.id)
                        }

                        if shouldShowDraft {
                            TranscriptSegmentRow(
                                segment: LiveTranscriptSegment(
                                    id: UUID(),
                                    originalText: originalText,
                                    translatedText: translatedText
                                ),
                                compactMode: compactMode,
                                isDraft: true
                            )
                            .id("draft-segment")
                        }
                    }
                    .padding(12)
                }
            }
            .onAppear {
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: segments) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: translatedText) { _, _ in
                scrollToBottom(proxy: proxy)
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            if shouldShowDraft {
                proxy.scrollTo("draft-segment", anchor: .bottom)
            } else if let last = segments.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

private struct TranscriptSegmentRow: View {
    let segment: LiveTranscriptSegment
    let compactMode: Bool
    var isDraft: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TranscriptCell(
                text: segment.originalText,
                foreground: .white.opacity(0.76),
                compactMode: compactMode,
                isDraft: isDraft
            )

            TranscriptCell(
                text: segment.translatedText,
                foreground: .white,
                compactMode: compactMode,
                isDraft: isDraft,
                isEmphasized: true
            )
        }
    }
}

private struct TranscriptCell: View {
    let text: String
    let foreground: Color
    let compactMode: Bool
    var isDraft: Bool = false
    var isEmphasized: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: compactMode ? 13 : (isEmphasized ? 15 : 14), weight: isEmphasized ? .semibold : .regular))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(backgroundStyle)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var backgroundStyle: some ShapeStyle {
        if isDraft {
            return AnyShapeStyle(Color.accentColor.opacity(0.12))
        }

        return AnyShapeStyle(Color.white.opacity(0.055))
    }
}

private struct OverlayEmptyTranscriptState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.tr("Waiting for call audio", "Жду звук звонка"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))

            Text(L.tr("The feed will appear here as aligned original and translated text.", "Здесь появится поток речи с синхронными колонками оригинала и перевода."))
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct OverlayStatusChip: View {
    let text: String
    let icon: String
    var isAccent: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(isAccent ? Color.accentColor : Color.white.opacity(0.75))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.06))
        .clipShape(Capsule())
    }
}

private class SubtitlePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

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
            let visibleFrame = screen.visibleFrame
            let panelWidth = min(max(visibleFrame.width * 0.34, 460), 720) + 18
            let panelHeight = visibleFrame.height - 36
            let x = visibleFrame.maxX - panelWidth
            let y = visibleFrame.minY + 18

            let newPanel = SubtitlePanel(
                contentRect: NSRect(x: x, y: y, width: panelWidth, height: panelHeight),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )

            newPanel.isFloatingPanel = true
            newPanel.level = .popUpMenu
            newPanel.backgroundColor = .clear
            newPanel.isOpaque = false
            newPanel.hasShadow = false
            newPanel.animationBehavior = .none
            newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            newPanel.isMovableByWindowBackground = false
            newPanel.hidesOnDeactivate = false
            newPanel.ignoresMouseEvents = false
            newPanel.contentView = hostingView
            self.panel = newPanel

            NotificationCenter.default.addObserver(self, selector: #selector(hideIfStopped), name: .liveTranslatorDidStop, object: nil)
        }

        panel?.orderFrontRegardless()
    }

    func updateWindowSize(_ size: CGSize) {
        guard let panel = panel, let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        let width = min(max(visibleFrame.width * 0.34, 460), 720) + 18
        let height = visibleFrame.height - 36
        let x = visibleFrame.maxX - width
        let y = visibleFrame.minY + 18

        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true, animate: false)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    @objc private func hideIfStopped() {
        hide()
    }
}
