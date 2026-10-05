import SwiftUI
import AppKit
import Combine
import Foundation

// MARK: - Waveform View

struct WaveformView: View {
    let levels: [Float]
    let barCount: Int = 24
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                let level = index < levels.count ? levels[index] : 0
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(
                        LinearGradient(
                            colors: [SW.accent, SW.accentBlue.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3, height: max(2, CGFloat(level) * 18))
                    .animation(reduceMotion ? nil : .spring(response: 0.15, dampingFraction: 0.6), value: level)
            }
        }
        .frame(width: CGFloat(barCount * 6 - 3), height: 20)
    }
}

// MARK: - Recording Overlay Content

struct RecordingOverlayContent: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var recorder: AudioRecorder
    @ObservedObject fileprivate var geometry: OverlayGeometry
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    @State private var pulse = false
    @State private var reservesBackgroundProcessingSlot = false

    var body: some View {
        OverlayCapsuleLayout(size: geometry.size, reduceMotion: reduceMotion, onNaturalSize: { size, reduced in
            geometry.retarget(size, reduceMotion: reduced)
        }) {
            overlayContents
        }
        .background(
            ZStack(alignment: .leading) {
                Capsule().fill(.ultraThinMaterial)
                Capsule().fill(Color.black.opacity(0.45))
                if appState.isProcessingActive {
                    processingProgressFill(cornerRadius: SW.radiusLarge, opacity: 0.10)
                }
            }
        )
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
        .environment(\.colorScheme, .dark)
        .padding(6)
        .onAppear {
            reservesBackgroundProcessingSlot = appState.backgroundProcessingCount > 0
            updatePulse()
        }
        .onChange(of: reduceMotion) { _, _ in updatePulse() }
        .onChange(of: appState.state) { _, state in
            if state == .recording {
                reservesBackgroundProcessingSlot = appState.backgroundProcessingCount > 0
            }
        }
    }

    private var overlayContents: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .scaleEffect(appState.state == .recording && pulse ? 1.4 : 1.0)
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
            }
            .opacity(appState.state == .processing || appState.state == .typing || appState.backgroundProcessingCount > 0 ? (pulse ? 1.0 : 0.3) : 1.0)

            if appState.state == .recording {
                WaveformView(levels: recorder.audioLevels)
                    .overlay {
                        if recorder.isTooQuiet {
                            recordingQualityBadge("speaker.slash.fill", L.tr("Low", "Тихо"))
                        } else if recorder.isTooNoisy {
                            recordingQualityBadge("waveform.badge.exclamationmark", L.tr("Noise", "Шум"))
                        }
                    }

                if appState.backgroundProcessingCount > 0 || reservesBackgroundProcessingSlot {
                    backgroundProcessingPill
                        .opacity(appState.backgroundProcessingCount > 0 ? 1 : 0)
                        .accessibilityHidden(appState.backgroundProcessingCount == 0)
                }

                Text(formatDuration(recorder.recordingDuration))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                
                cancelButton
            } else if appState.state == .processing || appState.state == .typing || appState.backgroundProcessingCount > 0 {
                Text(primaryStatusText)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)

                if appState.state == .processing || appState.backgroundProcessingCount > 0 {
                    processingCancelButton
                }
            } else {
                Text(statusText).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
            }
            
            if let _ = appState.lastError {
                HStack(spacing: 8) {
                    if recorder.isMicrophoneDenied || appState.isMicrophoneDenied {
                        Button {
                            appState.openMicrophoneSettings()
                        } label: {
                            Text(L.tr("Settings", "Настройки"))
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.red.opacity(0.3))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.swPlainInteractive)
                    }
                    
                    Button { appState.clearError() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.6))
                    }.buttonStyle(.swPlainInteractive)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .fixedSize()
        .opacity(geometry.contentOpacity)
    }

    private func updatePulse() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            pulse = !reduceMotion
        }
    }

    private func recordingQualityBadge(_ icon: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9))
            Text(label).font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(SW.warning)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.black.opacity(0.8)))
    }

    private var statusColor: Color {
        if let _ = appState.lastError { return SW.danger }
        if appState.state == .recording { return SW.danger }
        if appState.backgroundProcessingCount > 0 { return SW.warning }
        switch appState.state {
        case .starting: return SW.warning
        case .recording: return SW.danger
        case .processing: return SW.warning
        case .typing: return SW.accent
        case .idle: return SW.secondaryText
        }
    }

    private var statusText: String {
        if let error = appState.lastError { return error }
        if appState.backgroundProcessingCount > 0 {
            return localizedProcessingStage
        }
        switch appState.state {
        case .starting: return L.tr("Starting microphone...", "Запуск микрофона...")
        case .recording: return L.tr("Recording...", "Запись...")
        case .processing: return localizedProcessingStage
        case .typing: return L.tr("Typing...", "Печать...")
        case .idle: return ""
        }
    }

    private var localizedProcessingStage: String {
        switch appState.processingStage {
        case .converting: return L.tr("Converting...", "Конвертация...")
        case .preparing: return L.tr("Preparing local model...", "Подготовка локальной модели...")
        case .transcribing: return L.tr("Transcribing...", "Транскрибация...")
        case .postProcessing: return L.tr("Post-processing...", "Постобработка...")
        case .none: return L.tr("Processing...", "Обработка...")
        }
    }

    private var primaryStatusText: String {
        if appState.state == .typing {
            return L.tr("Typing...", "Печать...")
        }

        return localizedProcessingStage
    }

    private var backgroundProcessingPill: some View {
        HStack(spacing: 5) {
            ProgressView()
                .controlSize(.mini)
                .tint(SW.warning)
                .scaleEffect(0.62)
                .frame(width: 10, height: 10)

            Text(backgroundProcessingLabel)
                .font(.system(size: 10, weight: .bold))
                .lineLimit(1)
        }
        .foregroundStyle(SW.warning)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: SW.radiusSmall, style: .continuous)
                    .fill(SW.warning.opacity(0.15))
                processingProgressFill(cornerRadius: SW.radiusSmall, opacity: 0.12)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: SW.radiusSmall, style: .continuous))
    }

    private var backgroundProcessingLabel: String {
        appState.backgroundProcessingCount > 1
            ? L.tr("Processing \(appState.backgroundProcessingCount)", "Обработка \(appState.backgroundProcessingCount)")
            : L.tr("Processing", "Обработка")
    }

    private var visibleProcessingProgress: CGFloat {
        guard appState.isProcessingActive else { return 0 }
        return CGFloat(max(0.04, min(appState.processingProgress, 1)))
    }

    private func processingProgressFill(cornerRadius: CGFloat, opacity: Double) -> some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(opacity))
                .frame(width: proxy.size.width * visibleProcessingProgress)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.24), value: appState.processingProgress)
    }

    private var cancelButton: some View {
        Button {
            appState.cancelRecording()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 22, height: 22)
                .background(Circle().fill(.white.opacity(0.1)))
                .contentShape(Circle())
        }
        .buttonStyle(.swPlainInteractive)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private var processingCancelButton: some View {
        Button {
            appState.cancelProcessing()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 22, height: 22)
                .background(Circle().fill(.white.opacity(0.1)))
                .contentShape(Circle())
        }
        .buttonStyle(.swPlainInteractive)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        let tenths = Int(duration * 10) % 10
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d.%1d", hours, minutes, seconds, tenths)
        } else {
            return String(format: "%02d:%02d.%1d", minutes, seconds, tenths)
        }
    }
}

// MARK: - Ghost Panel (never becomes key/main — invisible to window manager)

private class GhostPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Floating Overlay Window Controller

@MainActor
final class OverlayWindowController: NSObject, ObservableObject {
    private var panel: NSPanel?
    private var anchorScreen: NSScreen?
    private let geometry = OverlayGeometry()
    private let topMargin: CGFloat = 12

    func show(appState: AppState) {
        if panel == nil {
            let content = RecordingOverlayContent(recorder: appState.recorder, geometry: geometry)
                .environmentObject(appState)

            let hostingView = NSHostingView(rootView: content)
            hostingView.sizingOptions = .intrinsicContentSize

            guard let frame = overlayFrame(size: hostingView.fittingSize) else { return }

            let newPanel = GhostPanel(
                contentRect: frame,
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
            geometry.onSizeChange = { [weak self] size in
                guard let self, let panel = self.panel, panel.isVisible,
                      let frame = self.overlayFrame(size: size), panel.frame != frame else { return }
                panel.setFrame(frame, display: true)
            }
        }

        if panel?.isVisible != true { anchorScreen = nil }
        if let size = panel?.contentView?.fittingSize, let frame = overlayFrame(size: size) {
            panel?.setFrame(frame, display: true)
        }
        geometry.setPresented(true)
        panel?.orderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
        geometry.setPresented(false)
        anchorScreen = nil
    }

    private func overlayFrame(size: NSSize) -> NSRect? {
        let mouseLocation = NSEvent.mouseLocation
        let screen = anchorScreen ?? NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return nil }
        anchorScreen = screen

        let visibleFrame = screen.visibleFrame
        let x = visibleFrame.midX - (size.width / 2)
        let y = visibleFrame.maxY - size.height - topMargin
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
}


@MainActor
private final class OverlayGeometry: ObservableObject {
    @Published private(set) var size: CGSize?
    var contentOpacity: Double {
        guard let size else { return 1 }
        return min(1, max(0, Double((size.width - target.width + 18) / 18)))
    }
    var onSizeChange: ((CGSize) -> Void)?
    private let spring = Spring(response: 0.38, dampingRatio: 0.76)
    private var target = CGSize.zero
    private var origin = CGSize.zero
    private var velocity = AnimatablePair<Double, Double>(0, 0)
    private var startedAt: TimeInterval = 0
    private var animation: OverlayResizeAnimation?
    private var presented = false

    func setPresented(_ presented: Bool) {
        self.presented = presented
        if !presented {
            animation?.stop()
            animation = nil
            if size != nil { publish(target) }
        }
    }

    func retarget(_ target: CGSize, reduceMotion: Bool) {
        guard target.width > 0, target.height > 0 else { return }
        guard self.target != target || reduceMotion && animation != nil else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = max(0, now - startedAt)
        let delta = AnimatablePair(Double(self.target.width - origin.width), Double(self.target.height - origin.height))
        let currentVelocity = animation != nil ? spring.velocity(target: delta, initialVelocity: velocity, time: elapsed) : .zero
        let current = animation != nil ? sampled(at: elapsed) : size
        animation?.stop()
        animation = nil
        self.target = target
        guard presented, !reduceMotion, let current else { publish(target); return }
        origin = current
        velocity = currentVelocity
        startedAt = now
        let displacement = AnimatablePair(Double(target.width - origin.width), Double(target.height - origin.height))
        let duration = spring.settlingDuration(target: displacement, initialVelocity: velocity, epsilon: 0.1)
        let driver = OverlayResizeAnimation(duration: duration) { [weak self] elapsed, finished in
            guard let self else { return }
            self.publish(finished ? self.target : self.sampled(at: elapsed))
            if finished { self.animation = nil }
        }
        animation = driver
        driver.start()
    }

    private func sampled(at elapsed: TimeInterval) -> CGSize {
        let delta = AnimatablePair(Double(target.width - origin.width), Double(target.height - origin.height))
        let value = spring.value(target: delta, initialVelocity: velocity, time: elapsed)
        return CGSize(width: origin.width + value.first, height: origin.height + value.second)
    }

    private func publish(_ size: CGSize) {
        onSizeChange?(CGSize(width: size.width + 12, height: size.height + 12))
        self.size = size
    }
}

private final class OverlayResizeAnimation: NSAnimation {
    private let sample: @MainActor (TimeInterval, Bool) -> Void
    init(duration: TimeInterval, sample: @escaping @MainActor (TimeInterval, Bool) -> Void) {
        self.sample = sample
        super.init(duration: duration, animationCurve: .linear)
        animationBlockingMode = .nonblocking
        frameRate = 60
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var currentProgress: NSAnimation.Progress {
        get { super.currentProgress }
        set {
            super.currentProgress = newValue
            MainActor.assumeIsolated { sample(Double(newValue) * duration, newValue >= 1) }
        }
    }
}

private struct OverlayCapsuleLayout: Layout {
    var size: CGSize?
    var reduceMotion: Bool
    var onNaturalSize: @MainActor (CGSize, Bool) -> Void

    struct Cache {
        var naturalSize = CGSize.zero
        var reduceMotion = false
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let natural = content.sizeThatFits(.unspecified)
        if natural != cache.naturalSize || reduceMotion != cache.reduceMotion {
            cache.naturalSize = natural
            cache.reduceMotion = reduceMotion
            let reduced = reduceMotion
            DispatchQueue.main.async { onNaturalSize(natural, reduced) }
        }
        return size ?? natural
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        subviews.first?.place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center, proposal: .unspecified)
    }
}
