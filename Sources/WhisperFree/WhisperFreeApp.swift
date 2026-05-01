import SwiftUI
import AppKit
import Combine
import Foundation

@main
struct WhisperFreeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared

    init() {
        print("🚀 WhisperKillerApp initializing...")
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            MenuBarIconView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    static private(set) var shared: AppDelegate?

    private var overlayController = OverlayWindowController()
    private var setupWizardController: SetupWizardWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var historyWindowController: HistoryWindowController?
    private var fileTranscriptionController: FileTranscriptionWindowController?
    private var accessibilityDragHelperController: AccessibilityDragHelperWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        print("🚀 applicationDidFinishLaunching...")

        // Ensure app can run without dock icon but with menu bar
        NSApp.setActivationPolicy(.accessory)

        // Bridge AppState.showOverlayWindow → OverlayWindowController
        let appState = AppState.shared
        appState.$showOverlayWindow
            .sink { [weak self] show in
                guard let self = self else { return }
                if show {
                    self.overlayController.show(appState: appState)
                } else {
                    self.overlayController.hide()
                }
            }
            .store(in: &appState.overlayCancellables)

        // Bridge AppState.showLiveTranslatorOverlay → SubtitleOverlayController
        appState.$showLiveTranslatorOverlay
            .sink { show in
                if show {
                    SubtitleOverlayController.shared.show()
                } else {
                    SubtitleOverlayController.shared.hide()
                }
            }
            .store(in: &appState.overlayCancellables)

        // Show setup wizard if needed
        if !appState.settings.setupCompleted {
            print("🪄 Showing Setup Wizard...")
            showSetupWizard()
        }
        print("✨ Launch sequence complete")
    }

    func applicationWillTerminate(_ notification: Notification) {
        print("🛑 applicationWillTerminate: Cleaning up resources...")
        AppState.shared.stopAll()
    }

    func showSetupWizard() {
        if setupWizardController == nil {
            setupWizardController = SetupWizardWindowController()
        }
        setupWizardController?.show()
    }

    func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.show()
    }

    func showHistory() {
        if historyWindowController == nil {
            historyWindowController = HistoryWindowController()
        }
        historyWindowController?.show()
    }

    func showFileTranscription() {
        if fileTranscriptionController == nil {
            fileTranscriptionController = FileTranscriptionWindowController()
        }
        fileTranscriptionController?.show()
    }

    func showAccessibilityDragHelper() {
        if accessibilityDragHelperController == nil {
            accessibilityDragHelperController = AccessibilityDragHelperWindowController()
        }
        accessibilityDragHelperController?.show()
    }

    func hideAccessibilityDragHelper() {
        accessibilityDragHelperController?.close()
        accessibilityDragHelperController = nil
    }
}

// MARK: - Window Controllers

@MainActor
final class SetupWizardWindowController: NSObject {
    private var window: NSWindow?

    func show() {
        if window != nil {
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SetupWizardView(
            modelManager: AppState.shared.modelManager,
            onComplete: { [weak self] in
                self?.close()
            }
        ).environmentObject(AppState.shared)

        let hostingView = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.contentView = hostingView
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
        window = nil
    }
}

@MainActor
final class SettingsWindowController: NSObject {
    private var window: NSWindow?

    func show() {
        if window != nil {
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let appState = AppState.shared
        let view = SettingsView(modelManager: appState.modelManager, recorder: appState.recorder).environmentObject(appState)
        let hostingView = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 550),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.contentView = hostingView
        window.title = L.tr("WhisperKiller Settings", "Настройки WhisperKiller")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class HistoryWindowController: NSObject {
    private var window: NSWindow?

    func show() {
        if window != nil {
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = HistoryView().environmentObject(AppState.shared)
        let hostingView = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.contentView = hostingView
        window.title = L.tr("Transcription History", "История транскрибации")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class FileTranscriptionWindowController: NSObject {
    private var window: NSWindow?

    func show() {
        if window != nil {
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = FileTranscriptionView().environmentObject(AppState.shared)
        let hostingView = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.contentView = hostingView
        window.title = L.tr("Transcribe File", "Транскрибировать файл")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class AccessibilityDragHelperWindowController: NSObject {
    private var panel: NSPanel?
    private var repositionTimer: Timer?

    func show() {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            position(panel)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = AccessibilityDragHelperView(
            onOpenSettings: {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                NSWorkspace.shared.open(url)
            },
            onClose: { [weak self] in
                self?.close()
            }
        )

        let hostingView = NSHostingView(rootView: view)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 184),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        self.panel = panel
        position(panel)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        startRepositioning()
    }

    func close() {
        repositionTimer?.invalidate()
        repositionTimer = nil
        panel?.close()
        panel = nil
    }

    private func position(_ panel: NSPanel) {
        let targetFrame = systemSettingsWindowFrame() ?? appWindowFrame(excluding: panel)
        let size = panel.frame.size

        if let targetFrame {
            let screenFrame = visibleFrame(containing: targetFrame)
            let rightX = targetFrame.maxX + 16
            let leftX = targetFrame.minX - size.width - 16
            let x: CGFloat

            if rightX + size.width <= screenFrame.maxX - 12 {
                x = rightX
            } else if leftX >= screenFrame.minX + 12 {
                x = leftX
            } else {
                x = min(max(rightX, screenFrame.minX + 12), screenFrame.maxX - size.width - 12)
            }

            let y = min(max(targetFrame.midY - size.height / 2, screenFrame.minY + 16), screenFrame.maxY - size.height - 16)
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            let screenFrame = NSScreen.main?.visibleFrame ?? .zero
            let x = min(max(screenFrame.maxX - size.width - 24, screenFrame.minX + 12), screenFrame.maxX - size.width - 12)
            let y = min(max(screenFrame.midY - size.height / 2, screenFrame.minY + 16), screenFrame.maxY - size.height - 16)
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    private func appWindowFrame(excluding panel: NSPanel) -> NSRect? {
        NSApp.windows
            .filter { $0.isVisible && $0 !== panel && !$0.frame.isEmpty }
            .sorted { $0.frame.maxX > $1.frame.maxX }
            .first?
            .frame
    }

    private func visibleFrame(containing rect: NSRect) -> NSRect {
        let midpoint = NSPoint(x: rect.midX, y: rect.midY)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(midpoint) }) {
            return screen.visibleFrame
        }

        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(rect) }) {
            return screen.visibleFrame
        }

        return NSScreen.main?.visibleFrame ?? .zero
    }

    private func startRepositioning() {
        repositionTimer?.invalidate()
        var ticks = 0
        repositionTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self, let panel = self.panel else {
                    timer.invalidate()
                    return
                }

                self.position(panel)
                ticks += 1

                if ticks >= 24 || self.systemSettingsWindowFrame() != nil {
                    timer.invalidate()
                    self.repositionTimer = nil
                }
            }
        }
    }

    private func systemSettingsWindowFrame() -> NSRect? {
        guard let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for window in windowInfo {
            guard let owner = window[kCGWindowOwnerName as String] as? String,
                  owner == "System Settings" || owner == "System Preferences",
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let cgRect = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else { continue }

            return appKitRect(fromWindowServerRect: cgRect)
        }

        return nil
    }

    private func appKitRect(fromWindowServerRect rect: CGRect) -> NSRect {
        let screens = NSScreen.screens
        let screen = screens.first { screen in
            let topLeftY = screen.frame.maxY - rect.minY
            let candidate = NSRect(x: rect.minX, y: topLeftY - rect.height, width: rect.width, height: rect.height)
            return screen.frame.intersects(candidate)
        } ?? NSScreen.main

        guard let screen else {
            return NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
        }

        let y = screen.frame.maxY - rect.minY - rect.height
        return NSRect(x: rect.minX, y: y, width: rect.width, height: rect.height)
    }
}

private struct AccessibilityDragHelperView: View {
    let onOpenSettings: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "hand.draw.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SW.accent)
                Text(L.tr("Drag into Accessibility", "Перетащите в Accessibility"))
                    .font(SW.titleFont)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(SW.secondaryText)
                }
                .buttonStyle(.plain)
            }

            Text(L.tr("Drag WhisperKiller from this card into the Accessibility list, then enable the toggle.", "Перетащите WhisperKiller из этой карточки в список Accessibility, затем включите переключатель."))
                .font(SW.compactFont)
                .foregroundStyle(SW.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                draggableAppTile

                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .background(SW.rowBackground)
                        .clipShape(RoundedRectangle(cornerRadius: SW.radiusSmall, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(L.tr("Open Accessibility settings", "Открыть настройки Accessibility"))
            }
        }
        .padding(14)
        .frame(width: 300)
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                SW.windowBackground.opacity(0.72)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: SW.radiusLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SW.radiusLarge, style: .continuous)
                .strokeBorder(SW.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
    }

    private var draggableAppTile: some View {
        HStack(spacing: 9) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text("WhisperKiller")
                    .font(.system(size: 12, weight: .semibold))
                Text(L.tr("Drag me", "Тащи отсюда"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(SW.secondaryText)
            }

            Spacer(minLength: 0)
            Image(systemName: "arrow.up.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(SW.accent)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(SW.rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: SW.radiusMedium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SW.radiusMedium, style: .continuous)
                .strokeBorder(SW.accent.opacity(0.22), lineWidth: 1)
        )
        .onDrag {
            NSItemProvider(object: Bundle.main.bundleURL as NSURL)
        }
    }
}

// MARK: - Menu Bar Icon

struct MenuBarIconView: View {
    @EnvironmentObject var appState: AppState
    @State private var pulseOpacity: CGFloat = 1.0
    @State private var timer: Timer?
    @State private var pulseUp = false

    var body: some View {
        Image(nsImage: createMenuImage())
            .onAppear { startPulse() }
            .onChange(of: appState.state) { _, _ in startPulse() }
    }

    private var isAnimated: Bool {
        appState.state == .recording || appState.state == .processing
    }

    private func startPulse() {
        timer?.invalidate()
        if isAnimated {
            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                Task { @MainActor in
                    if pulseUp {
                        pulseOpacity += 0.04
                        if pulseOpacity >= 1.0 { pulseUp = false }
                    } else {
                        pulseOpacity -= 0.04
                        if pulseOpacity <= 0.3 { pulseUp = true }
                    }
                }
            }
        } else {
            pulseOpacity = 1.0
        }
    }

    private var dotColor: NSColor {
        switch appState.state {
        case .recording: return .systemRed
        case .processing: return .systemOrange
        default: return .clear
        }
    }

    private func createMenuImage() -> NSImage {
        let size = NSSize(width: 22, height: 22)
        let isMonochrome = appState.settings.useMonochromeMenuIcon
        let image = NSImage(size: size)
        image.lockFocus()

        if isMonochrome {
            // SF Symbol for native monochrome look
            if let sfImage = NSImage(systemSymbolName: "microphone.fill", accessibilityDescription: nil) {
                let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                let configured = sfImage.withSymbolConfiguration(config) ?? sfImage
                let sfSize = configured.size
                let x = (size.width - sfSize.width) / 2
                let y = (size.height - sfSize.height) / 2
                configured.draw(in: NSRect(x: x, y: y, width: sfSize.width, height: sfSize.height),
                               from: .zero, operation: .sourceOver, fraction: 1.0)
            }
        } else {
            // Colored app icon
            if let icon = NSApp.applicationIconImage {
                let iconRect = NSRect(x: 2, y: 2, width: 18, height: 18)
                icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            }
        }

        // Draw status dot ONLY during recording or processing (skip in monochrome — isTemplate kills colors)
        if !isMonochrome && (appState.state == .recording || appState.state == .processing) {
            let dotSize: CGFloat = 6
            let dotX = size.width - dotSize - 1
            let dotY: CGFloat = 1
            let dotRect = NSRect(x: dotX, y: dotY, width: dotSize, height: dotSize)

            NSColor.white.setFill()
            NSBezierPath(ovalIn: dotRect.insetBy(dx: -0.5, dy: -0.5)).fill()

            let opacity = (appState.state == .recording || appState.state == .processing) ? pulseOpacity : 1.0
            dotColor.withAlphaComponent(opacity).setFill()
            NSBezierPath(ovalIn: dotRect).fill()
        }

        image.unlockFocus()
        image.isTemplate = isMonochrome
        return image
    }
}
