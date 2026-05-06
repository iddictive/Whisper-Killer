import SwiftUI
import AVFoundation

struct SetupWizardView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var modelManager: ModelManager
    @ObservedObject private var dependencyInstaller = DependencyInstaller.shared
    var onComplete: () -> Void

    @State private var currentStep = 0
    @State private var apiKey = ""
    @State private var selectedEngine: TranscriptionEngineType = .cloud
    @State private var selectedModel: LocalModelSize = .base
    @State private var apiValidationState: OpenAIAPIKeyValidationState = .idle
    @State private var micGranted = false
    @State private var homebrewInstalled = false
    @State private var whisperInstalled = false
    @State private var animateGlow = false

    private let totalSteps = 5

    // MARK: - Colors

    private let accentGold = SW.accent
    private let accentPink = SW.accentBlue
    private let accentMag  = SW.accentIndigo
    private let bgDark = SW.bg
    private let bgCard = SW.card
    private let bgCardHover = SW.cardHover
    private let borderSubtle = SW.border
    private let textPrimary = Color.white
    private let textSecondary = Color(white: 0.55)

    private var apiValidationText: String? {
        switch apiValidationState {
        case .idle:
            return apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : L.tr("Key not checked yet.", "Ключ ещё не проверен.")
        case .checking:
            return L.tr("Checking key…", "Проверяю ключ…")
        case .valid:
            return L.tr("Key is valid.", "Ключ валиден.")
        case .invalid:
            return L.tr("Key is invalid.", "Ключ невалиден.")
        case .networkError(let message):
            return L.tr("Could not reach OpenAI. \(message)", "Не удалось связаться с OpenAI. \(message)")
        case .failed(let statusCode):
            return L.tr("Validation failed (HTTP \(statusCode)).", "Проверка не удалась (HTTP \(statusCode)).")
        }
    }

    private var apiValidationColor: Color {
        switch apiValidationState {
        case .valid:
            return .green
        case .invalid, .networkError, .failed:
            return .red
        case .idle, .checking:
            return textSecondary
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            bgDark.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.top, 22)
                    .padding(.bottom, 12)

                progressBar
                    .padding(.horizontal, 40)
                    .padding(.bottom, 16)

                stepContent
                    .frame(maxHeight: .infinity)
                    .padding(.bottom, 68)
            }

            NonDraggableContainer {
                bottomBar
                    .padding(.horizontal, 36)
                    .padding(.vertical, 12)
            }
            .frame(height: 64)
            .background(bgDark.opacity(0.97))
        }
        .frame(width: 580, height: 600)
        .preferredColorScheme(.dark)
        .onAppear {
            refreshStatus()
            apiKey = appState.settings.apiKey
            selectedEngine = appState.settings.engineType
            selectedModel = LocalModelSize.recommended
            animateGlow = true
        }
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            if currentStep == 1 || currentStep == 4 {
                refreshStatus()
                // Auto-advance from permissions to engine if both granted
                if currentStep == 1 && appState.isHotkeyTrusted && micGranted {
                    withAnimation(.spring(response: 0.35)) {
                        currentStep = 2
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        if currentStep == 0 {
            NonDraggableContainer {
                welcomeStep
                    .padding(.horizontal, 36)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        } else {
            ScrollView(showsIndicators: false) {
                NonDraggableContainer {
                    Group {
                        switch currentStep {
                        case 1: permissionsStep
                        case 2: engineStep
                        case 3: apiKeyStep
                        case 4: readyStep
                        default: EmptyView()
                        }
                    }
                    .padding(.horizontal, 36)
                    .padding(.bottom, 78)
                }
            }
        }
    }

    // ═══════════════════════════════════════════════
    // MARK: – Header
    // ═══════════════════════════════════════════════

    private var header: some View {
        VStack(spacing: 6) {
            ZStack {
                // Outer ring glow
                Circle()
                    .stroke(LinearGradient(colors: [accentGold, accentPink], startPoint: .top, endPoint: .bottom).opacity(0.3), lineWidth: 2)
                    .frame(width: 56, height: 56)
                    .blur(radius: 3)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accentGold.opacity(0.2), accentPink.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)

                Image(systemName: stepIcon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(accentPink)
            }

            Text(stepTitle)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(textPrimary)

            Text(stepSubtitle)
                .font(.system(size: 12))
                .foregroundStyle(textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 40)
        }
    }

    private var stepIcon: String {
        ["waveform.circle.fill", "lock.shield", "cpu", "key.fill", "checkmark.seal.fill"][currentStep]
    }

    private var stepTitle: String {
        ["Whisper Free", "Permissions", "Engine", "API Key", "Ready"][currentStep]
            .replacingOccurrences(of: "Permissions", with: L.tr("Permissions", "Разрешения"))
            .replacingOccurrences(of: "Engine", with: L.tr("Engine", "Движок"))
            .replacingOccurrences(of: "API Key", with: L.tr("API Key", "API Key"))
            .replacingOccurrences(of: "Ready", with: L.tr("Ready", "Готово"))
    }

    private var stepSubtitle: String {
        let subtitles = [
            "AI voice-to-text, built for macOS",
            "Two quick permissions to enable",
            "Cloud or local — your choice",
            "For cloud transcription & AI modes",
            "Everything's set up"
        ]

        return [
            L.tr(subtitles[0], "Голос в текст с AI для macOS"),
            L.tr(subtitles[1], "Нужно выдать два разрешения"),
            L.tr(subtitles[2], "Облако или локально — на ваш выбор"),
            L.tr(subtitles[3], "Для облачной транскрибации и AI-режимов"),
            L.tr(subtitles[4], "Всё готово к работе")
        ][currentStep]
    }

    // ═══════════════════════════════════════════════
    // MARK: – Progress bar
    // ═══════════════════════════════════════════════

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 4)

                // Fill
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [accentGold, accentPink, accentMag],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * CGFloat(currentStep + 1) / CGFloat(totalSteps), height: 4)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: currentStep)

                // Step dots
                HStack {
                    ForEach(0..<totalSteps, id: \.self) { step in
                        Circle()
                            .fill(step <= currentStep ? accentPink : Color.white.opacity(0.15))
                            .frame(width: 8, height: 8)
                            .overlay(
                                Circle()
                                    .fill(step == currentStep ? accentPink : .clear)
                                    .frame(width: 12, height: 12)
                                    .opacity(0.3)
                            )
                        if step < totalSteps - 1 { Spacer() }
                    }
                }
            }
        }
        .frame(height: 12)
    }

    // ═══════════════════════════════════════════════
    // MARK: – Step 0: Welcome
    // ═══════════════════════════════════════════════

    private var welcomeStep: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ],
            spacing: 10
        ) {
            featureCard(icon: "mic.fill", color: .red,
                        title: L.tr("\(appState.settings.hotkeyConfig.displayString) to record", "\(appState.settings.hotkeyConfig.displayString) для записи"),
                        desc: L.tr("Hold, Toggle, or Push-to-Talk — pick your style", "Удержание, toggle или push-to-talk — выберите свой режим"))
            featureCard(icon: "waveform", color: accentPink,
                        title: L.tr("AI transcription", "AI-транскрибация"),
                        desc: L.tr("Cloud (OpenAI) or Local (whisper.cpp with GPU/NPU)", "Облако (OpenAI) или локально (whisper.cpp с GPU/NPU)"))
            featureCard(icon: "sparkles", color: SW.accent,
                        title: L.tr("Smart post-processing", "Умная постобработка"),
                        desc: L.tr("Dictation · Email · Code · Notes — or create your own", "Dictation · Email · Code · Notes — или создайте свой режим"))
            featureCard(icon: "keyboard", color: .orange,
                        title: L.tr("Auto-paste anywhere", "Автовставка куда угодно"),
                        desc: L.tr("Result instantly typed into whichever app is focused", "Результат сразу печатается в активное приложение"))
        }
    }

    private func featureCard(icon: String, color: Color, title: String, desc: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(color.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(textPrimary)
                    .lineLimit(1)
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundStyle(textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .padding(13)
        .background(bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(borderSubtle, lineWidth: 1)
        )
    }

    // ═══════════════════════════════════════════════
    // MARK: – Step 1: Permissions
    // ═══════════════════════════════════════════════

    private var permissionsStep: some View {
        VStack(spacing: 14) {
            permissionBridgeCard(
                icon: "hand.raised.fill",
                title: L.tr("Accessibility", "Accessibility"),
                desc: L.tr("Drag WhisperKiller into the Accessibility list, then enable it.", "Перетащите WhisperKiller в список Accessibility и включите его."),
                granted: appState.isHotkeyTrusted,
                supportsAppDrag: true,
                actionTitle: L.tr("Open", "Открыть")
            ) {
                appState.requestAccessibilityPermission()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { refreshStatus() }
            }

            permissionBridgeCard(
                icon: "mic.fill",
                title: L.tr("Microphone", "Микрофон"),
                desc: L.tr("Use the native macOS prompt for voice capture.", "Разрешите доступ в системном запросе macOS."),
                granted: micGranted,
                supportsAppDrag: false,
                actionTitle: L.tr("Grant", "Выдать")
            ) {
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    DispatchQueue.main.async {
                        micGranted = granted
                        if !granted {
                            // If denied, guide to settings
                            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }

            Button {
                refreshStatus()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text(L.tr("Refresh", "Обновить"))
                }
                .font(.system(size: 12))
                .foregroundStyle(accentGold)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            if appState.isTranslocated {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.octagon.fill")
                            .foregroundStyle(.red)
                        Text(L.tr("App Translocation Detected", "Обнаружен App Translocation"))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.red)
                    }
                    Text(L.tr("To ensure permissions like Accessibility and Microphone work correctly, please move WhisperFree to your Applications folder.", "Чтобы разрешения вроде Accessibility и Microphone работали корректно, переместите WhisperFree в папку Applications."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button {
                        let url = URL(fileURLWithPath: "/Applications")
                        NSWorkspace.shared.open(url)
                    } label: {
                        Text(L.tr("Open Applications Folder", "Открыть папку Applications"))
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.15))
                            .foregroundStyle(.red)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                .background(Color.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.red.opacity(0.2), lineWidth: 1))
                .padding(.top, 8)
            }
        }
    }

    private func permissionBridgeCard(
        icon: String,
        title: String,
        desc: String,
        granted: Bool,
        supportsAppDrag: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(granted ? Color.accentColor.opacity(0.15) : Color.orange.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundStyle(granted ? Color.accentColor : .orange)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(textPrimary)
                    Text(desc).font(.system(size: 11)).foregroundStyle(textSecondary)
                }

                Spacer()

                if granted {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                        Text(L.tr("Granted", "Выдано"))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(Capsule())
                } else {
                    Button(action: action) {
                        Text(actionTitle)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color.orange)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            if !granted {
                HStack(spacing: 10) {
                    permissionTile(
                        icon: "app.fill",
                        title: "WhisperKiller",
                        subtitle: supportsAppDrag ? L.tr("Drag", "Перетащить") : L.tr("App", "Приложение"),
                        draggable: supportsAppDrag
                    )

                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(textSecondary)

                    permissionTile(
                        icon: supportsAppDrag ? "list.bullet.rectangle" : "switch.2",
                        title: supportsAppDrag ? L.tr("Accessibility", "Accessibility") : L.tr("macOS Prompt", "Запрос macOS"),
                        subtitle: supportsAppDrag ? L.tr("Drop here", "В список") : L.tr("Allow", "Разрешить"),
                        draggable: false
                    )
                }
            }
        }
        .padding(14)
        .background(bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(granted ? Color.accentColor.opacity(0.15) : borderSubtle, lineWidth: 1)
        )
    }

    private func permissionTile(icon: String, title: String, subtitle: String, draggable: Bool) -> some View {
        let tile = HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(draggable ? accentPink : textSecondary)
                .frame(width: 22, height: 22)
                .background((draggable ? accentPink : textSecondary).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(borderSubtle, lineWidth: 1))

        if draggable {
            return AnyView(tile.onDrag {
                NSItemProvider(object: Bundle.main.bundleURL as NSURL)
            })
        }

        return AnyView(tile)
    }

    // ═══════════════════════════════════════════════
    // MARK: – Step 2: Engine
    // ═══════════════════════════════════════════════

    private var engineStep: some View {
        VStack(spacing: 14) {
            // Engine picker
            HStack(spacing: 10) {
                enginePill(type: .cloud, icon: "cloud.fill", label: "Cloud")
                enginePill(type: .local, icon: "desktopcomputer", label: "Local")
                enginePill(type: .gigaAM, icon: TranscriptionEngineType.gigaAM.icon, label: "GigaAM")
            }

            // Engine details
            if selectedEngine == .cloud {
                cloudEngineCard
            } else if selectedEngine == .local {
                localEngineCard
            } else {
                gigaAMEngineCard
            }
        }
    }

    private func enginePill(type: TranscriptionEngineType, icon: String, label: String) -> some View {
        let selected = type == selectedEngine
        return Button {
            withAnimation(.spring(response: 0.3)) { selectedEngine = type }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 14))
                Text(label).font(.system(size: 13, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(selected ? accentGold.opacity(0.15) : bgCard)
            .foregroundStyle(selected ? accentGold : textSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(selected ? accentGold.opacity(0.4) : borderSubtle, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var cloudEngineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill").foregroundStyle(.yellow).font(.system(size: 11))
                Text(L.tr("Fast · Accurate · 100+ languages", "Быстро · Точно · 100+ языков"))
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(textSecondary)
            }

            tagRow(items: [
                ("checkmark", "OpenAI Whisper API", Color.accentColor),
                ("wifi", "Requires internet", .orange),
                ("key", "Requires API key", .orange),
            ])

            Text(L.tr("Audio is sent to OpenAI for processing. Great for maximum accuracy.", "Аудио отправляется в OpenAI для обработки. Хороший вариант для максимальной точности."))
                .font(.system(size: 11))
                .foregroundStyle(textSecondary)
        }
        .padding(16)
        .background(bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(borderSubtle, lineWidth: 1))
    }

    private var localEngineCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            localEngineStatusRow

            Text(L.tr("MODEL", "МОДЕЛЬ"))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(textSecondary)

            ForEach(LocalModelSize.allCases, id: \.self) { size in
                modelRow(size)
            }
        }
        .padding(16)
        .background(bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(borderSubtle, lineWidth: 1))
    }

    private var gigaAMEngineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: TranscriptionEngineType.gigaAM.icon).foregroundStyle(Color.accentColor).font(.system(size: 11))
                Text(L.tr("Russian · Local · Experimental", "Русский · Локально · Эксперимент"))
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(textSecondary)
            }

            tagRow(items: [
                ("text.bubble", "GigaAM-v3", Color.accentColor),
                ("terminal", "Python 3", .orange),
                ("arrow.down.circle", "Downloads model cache", .orange),
            ])

            Text(L.tr("Russian-focused recognition for comparison runs.", "Распознавание под русский для сравнительных прогонов."))
                .font(.system(size: 11))
                .foregroundStyle(textSecondary)
        }
        .padding(16)
        .background(bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(borderSubtle, lineWidth: 1))
    }

    private var localEngineStatusRow: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill").foregroundStyle(Color.accentColor).font(.system(size: 11))
                Text(L.tr("Private · Offline · Free", "Приватно · Офлайн · Бесплатно"))
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(textSecondary)
            }

            VStack(spacing: 8) {
                homebrewDependencyRow
                whisperCppDependencyRow
            }

            if !homebrewInstalled && !dependencyInstaller.homebrewStatus.isEmpty {
                Text(dependencyInstaller.homebrewStatus)
                    .font(.system(size: 10))
                    .foregroundStyle(textSecondary)
                    .lineLimit(2)
            } else if !whisperInstalled && !dependencyInstaller.whisperCppStatus.isEmpty {
                Text(dependencyInstaller.whisperCppStatus)
                    .font(.system(size: 10))
                    .foregroundStyle(textSecondary)
                    .lineLimit(2)
            }
        }
    }

    private var homebrewDependencyRow: some View {
        HStack(spacing: 10) {
            Image(systemName: homebrewInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(homebrewInstalled ? Color.accentColor : .red)
            Text(
                homebrewInstalled
                    ? L.tr("Homebrew detected", "Homebrew найден")
                    : L.tr("Homebrew not found", "Homebrew не найден")
            )
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(homebrewInstalled ? Color.accentColor : .red)
            Spacer()
            if !homebrewInstalled {
                if dependencyInstaller.isInstallingHomebrew {
                    Button {
                        refreshStatus()
                    } label: {
                        Text(L.tr("Refresh", "Обновить"))
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(accentPink.opacity(0.2))
                            .foregroundStyle(accentPink)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        installHomebrew()
                    } label: {
                        Text(L.tr("Install", "Установить"))
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(accentPink.opacity(0.2))
                            .foregroundStyle(accentPink)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .background(homebrewInstalled ? Color.accentColor.opacity(0.06) : Color.red.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var whisperCppDependencyRow: some View {
        HStack(spacing: 10) {
            Image(systemName: whisperInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(whisperInstalled ? Color.accentColor : .red)
            Text(
                whisperInstalled
                    ? L.tr("whisper-cpp detected", "whisper-cpp найден")
                    : L.tr("whisper-cpp not found", "whisper-cpp не найден")
            )
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(whisperInstalled ? Color.accentColor : .red)
            Spacer()
            if !whisperInstalled {
                if dependencyInstaller.isInstallingWhisperCpp {
                    ProgressView()
                        .controlSize(.mini)
                } else if homebrewInstalled {
                    Button {
                        installWhisperCpp()
                    } label: {
                        Text(L.tr("Install (brew)", "Установить (brew)"))
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(accentPink.opacity(0.2))
                            .foregroundStyle(accentPink)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .background(whisperInstalled ? Color.accentColor.opacity(0.06) : Color.red.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func modelRow(_ size: LocalModelSize) -> some View {
        let isCurrent = selectedModel == size
        let downloaded = modelManager.isModelDownloaded(size)
        _ = modelManager.isDownloading(size)
        _ = modelManager.progress(for: size)
        _ = modelManager.error(for: size)
        let isRecommended = size == LocalModelSize.recommended

        return HStack(spacing: 10) {
            Image(systemName: isCurrent ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 14))
                .foregroundStyle(isCurrent ? accentPink : textSecondary)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(size.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(textPrimary)
                    if isRecommended {
                    Text(L.tr("REC", "РЕК"))
                            .font(.system(size: 8, weight: .heavy, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(accentGold.opacity(0.2))
                            .foregroundStyle(accentGold)
                            .clipShape(Capsule())
                    }
                }
                HStack(spacing: 8) {
                    Text(size.sizeDescription)
                        .font(.system(size: 10))
                        .foregroundStyle(textSecondary)
                    Text(size.speedRating)
                        .font(.system(size: 9))
                }
            }

            Spacer()

            if downloaded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 14))
            } else if let state = modelManager.activeDownloads[size.rawValue] {
                if state.error != nil {
                    Text(L.tr("Error", "Ошибка")).font(.system(size: 10)).foregroundStyle(.red)
                } else if state.isPreparing {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text(L.tr("Preparing...", "Подготовка...")).font(.system(size: 9)).foregroundStyle(textSecondary)
                    }
                } else {
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 8) {
                            ProgressView(value: state.progress)
                                .progressViewStyle(.linear)
                                .frame(width: 80)
                            Button {
                                modelManager.cancelDownload(size)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                        HStack(spacing: 4) {
                            if state.speed > 0 {
                                Text(formatSpeed(state.speed))
                            }
                            if let remaining = state.timeRemaining {
                                Text("• \(formatDuration(remaining))")
                            }
                        }
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(textSecondary)
                    }
                }
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    Button {
                        modelManager.downloadModel(size)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 14))
                            Text(L.tr("Get", "Скачать"))
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(accentGold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(accentGold.opacity(0.15))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(isCurrent ? accentGold.opacity(0.06) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture {
            selectedModel = size
        }
    }

    private func tagRow(items: [(String, String, Color)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.1) { icon, text, color in
                HStack(spacing: 6) {
                    Image(systemName: icon).font(.system(size: 10)).foregroundStyle(color)
                    Text(text).font(.system(size: 11)).foregroundStyle(textSecondary)
                }
            }
        }
    }

    // ═══════════════════════════════════════════════
    // MARK: – Step 3: API Key
    // ═══════════════════════════════════════════════

    private var apiKeyStep: some View {
        VStack(spacing: 16) {
            if selectedEngine != .cloud {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill").foregroundStyle(accentGold)
                    Text(L.tr("Optional for local engines. Only needed for AI post-processing modes.", "Необязательно для локальных движков. Нужно только для AI-режимов постобработки."))
                        .font(.system(size: 12)).foregroundStyle(textSecondary)
                }
                .padding(14)
                .background(accentGold.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(accentGold.opacity(0.15), lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(L.tr("OpenAI API Key", "OpenAI API Key"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(textPrimary)

                HStack(spacing: 8) {
                    SecureField("sk-...", text: $apiKey)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .onChange(of: apiKey) { _, _ in
                            apiValidationState = .idle
                        }

                    Button {
                        testAPI()
                    } label: {
                        Group {
                            if apiValidationState == .checking {
                                ProgressView().controlSize(.mini).tint(accentGold)
                            } else {
                                Text(L.tr("Test", "Проверить"))
                                    .font(.system(size: 12, weight: .semibold))
                            }
                        }
                        .frame(width: 50)
                        .padding(.vertical, 10)
                        .background(accentGold.opacity(0.15))
                        .foregroundStyle(accentGold)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || apiValidationState == .checking)
                }

                if let result = apiValidationText {
                    HStack(spacing: 6) {
                        Image(systemName: apiValidationState == .valid ? "checkmark.circle.fill" : "info.circle.fill")
                        Text(result)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(apiValidationColor)
                }

                Link(destination: URL(string: "https://platform.openai.com/api-keys")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                        Text(L.tr("Get API key at platform.openai.com", "Получить API key на platform.openai.com"))
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(accentGold)
                }
            }
            .padding(16)
            .background(bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(borderSubtle, lineWidth: 1))

            if selectedEngine == .cloud && apiKey.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(L.tr("Cloud engine requires an API key", "Для облачного движка нужен API key"))
                        .font(.system(size: 12)).foregroundStyle(.orange)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // ═══════════════════════════════════════════════
    // MARK: – Step 4: Ready
    // ═══════════════════════════════════════════════

    private var readyStep: some View {
        VStack(spacing: 18) {
            // Checklist
            VStack(spacing: 8) {
                readyRow(L.tr("Accessibility", "Accessibility"), ok: appState.isHotkeyTrusted)
                readyRow(L.tr("Microphone", "Микрофон"), ok: micGranted)
                readyRow("\(L.tr("Engine", "Движок")): \(selectedEngine.localizedTitle)", ok: true)
                if selectedEngine == .cloud {
                    readyRow(L.tr("API Key", "API Key"), ok: !apiKey.isEmpty)
                } else if selectedEngine == .local {
                    readyRow("whisper-cpp", ok: whisperInstalled)
                    if modelManager.isModelDownloaded(selectedModel) {
                        readyRow("\(L.tr("Model", "Модель")): \(selectedModel.rawValue)", ok: true)
                    } else if let state = modelManager.activeDownloads[selectedModel.rawValue] {
                        VStack(alignment: .leading, spacing: 6) {
                            readyRow("\(L.tr("Model", "Модель")): \(selectedModel.rawValue)", ok: false)
                            HStack(spacing: 8) {
                                ProgressView(value: state.progress)
                                    .progressViewStyle(.linear)
                                    .controlSize(.small)
                                if state.speed > 0 {
                                    Text("\(formatSpeed(state.speed)) • \(formatDuration(state.timeRemaining ?? 0))")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(textSecondary)
                                }
                            }
                            .padding(.leading, 24)
                        }
                    } else {
                        readyRow("\(L.tr("Model", "Модель")): \(selectedModel.rawValue)", ok: false)
                    }
                } else {
                    readyRow("Python 3", ok: GigaAMTranscriber.findPythonBinary() != nil)
                    readyRow("GigaAM-v3", ok: true)
                }
            }
            .padding(16)
            .background(bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(borderSubtle, lineWidth: 1))

            // Shortcuts
            VStack(spacing: 10) {
                Text(L.tr("SHORTCUTS", "ГОРЯЧИЕ КЛАВИШИ"))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(textSecondary)
                shortcutBadge(
                    key: appState.settings.hotkeyConfig.displayString,
                    label: appState.settings.recordingMode.localizedTitle
                )
                Text(appState.settings.recordingMode.localizedDescription(hotkey: appState.settings.hotkeyConfig.displayString))
                    .font(.system(size: 11))
                    .foregroundStyle(textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(16)
            .background(bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(L.tr("You can change everything later in Settings", "Позже это всё можно изменить в настройках"))
                .font(.system(size: 11))
                .foregroundStyle(textSecondary)
        }
    }

    private func readyRow(_ label: String, ok: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.system(size: 14))
                .foregroundStyle(ok ? Color.accentColor : .orange)
            Text(label).font(.system(size: 13)).foregroundStyle(textPrimary)
            Spacer()
            Text(ok ? L.tr("Ready", "Готово") : L.tr("Skipped", "Пропущено"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ok ? Color.accentColor : .orange)
        }
    }

    private func shortcutBadge(key: String, label: String) -> some View {
        VStack(spacing: 6) {
            Text(key)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
                .foregroundStyle(textPrimary)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(textSecondary)
        }
    }

    // ═══════════════════════════════════════════════
    // MARK: – Bottom bar
    // ═══════════════════════════════════════════════

    private func formatSpeed(_ bytesPerSecond: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytesPerSecond)) + "/s"
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return "\(Int(duration))s"
        } else {
            let mins = Int(duration / 60)
            let secs = Int(duration.truncatingRemainder(dividingBy: 60))
            return "\(mins)m \(secs)s"
        }
    }

    private var bottomBar: some View {
        ZStack {
            Text("\(currentStep + 1)/\(totalSteps)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(textSecondary)

            HStack {
                if currentStep > 0 {
                    Button {
                        withAnimation(.spring(response: 0.35)) { currentStep -= 1 }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                        Text(L.tr("Back", "Назад")).font(.system(size: 13))
                    }
                    .foregroundStyle(textSecondary)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                if currentStep < totalSteps - 1 {
                    Button {
                        refreshStatus()
                        withAnimation(.spring(response: 0.35)) { currentStep += 1 }
                    } label: {
                        HStack(spacing: 6) {
                            Text(currentStep == 0 ? L.tr("Get Started", "Начать") : L.tr("Next", "Далее"))
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: [accentGold, accentPink],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        finishSetup()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                            Text(L.tr("Launch", "Запустить"))
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: [.green, .green.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // ═══════════════════════════════════════════════
    // MARK: – Actions
    // ═══════════════════════════════════════════════

    private func refreshStatus() {
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        dependencyInstaller.refreshHomebrewStatus()
        homebrewInstalled = dependencyInstaller.isHomebrewInstalled
        whisperInstalled = checkWhisperInstalled()
        modelManager.refreshDownloadedModels()
    }

    private func checkWhisperInstalled() -> Bool {
        LocalWhisper.findWhisperBinary() != nil
    }

    private func installWhisperCpp() {
        dependencyInstaller.installWhisperCpp {
            refreshStatus()
        }
    }

    private func installHomebrew() {
        dependencyInstaller.installHomebrew()
    }

    private func testAPI() {
        apiValidationState = .checking
        let currentKey = apiKey
        Task {
            let result = await OpenAIAPIKeyValidator.validate(currentKey)
            await MainActor.run {
                apiValidationState = result
            }
        }
    }

    private func finishSetup() {
        appState.settings.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        appState.settings.engineType = selectedEngine
        appState.settings.localModelSize = selectedModel

        // If no API key is provided, default to Raw mode to avoid AI processing errors
        if appState.settings.apiKey.isEmpty {
            print("whisper_debug: 🗝️ No API key provided, defaulting to Raw mode")
            appState.settings.selectedModeName = "Raw"
        }

        appState.settings.setupCompleted = true
        appState.saveSettings()
        appState.reloadHotkeyManager()
        print("whisper_debug: ✨ Setup wizard finished successfully")
        onComplete()
    }
}
