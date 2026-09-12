import SwiftUI
import AVFoundation

struct SetupWizardView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var modelManager: ModelManager
    @ObservedObject private var dependencyInstaller = DependencyInstaller.shared
    @ObservedObject private var parakeetModelManager = ParakeetModelManager.shared
    var onComplete: () -> Void

    @State private var currentStep = 0
    @State private var apiKey = ""
    @State private var selectedEngine: TranscriptionEngineType = .cloud
    @State private var selectedModel: LocalModelSize = .base
    @State private var selectedQwenModel: QwenASRModel = .fast
    @State private var apiValidationState: OpenAIAPIKeyValidationState = .idle
    @State private var micGranted = false
    @State private var homebrewInstalled = false
    @State private var whisperInstalled = false
    @State private var animateGlow = false
    @State private var hasStarredGitHub = false

    private let totalSteps = 5

    // MARK: - Design & Tokens

    private let accentColor = Color.accentColor
    private let cardBackground = Color.primary.opacity(0.045)
    private let subtleBorder = Color.primary.opacity(0.08)
    private let textPrimary = Color.primary
    private let textSecondary = Color.secondary

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
        ZStack {
            VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                .ignoresSafeArea()

            // Subtle ambient accent glow at top
            Circle()
                .fill(accentColor.opacity(0.09))
                .frame(width: 320, height: 320)
                .blur(radius: 50)
                .offset(y: -190)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                header
                    .padding(.top, 24)
                    .padding(.bottom, 12)

                progressBar
                    .padding(.horizontal, 40)
                    .padding(.bottom, 16)

                stepContent
                    .frame(maxHeight: .infinity)

                bottomBar
                    .padding(.horizontal, 36)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
            }
        }
        .frame(width: 580, height: 600)
        .onAppear {
            refreshStatus()
            apiKey = appState.settings.apiKey
            selectedEngine = appState.settings.engineType
            selectedModel = LocalModelSize.recommended
            selectedQwenModel = appState.settings.qwenASRModel
            parakeetModelManager.refresh()
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
            welcomeStep
                .padding(.horizontal, 36)
                .frame(maxHeight: .infinity, alignment: .top)
        } else {
            ScrollView(showsIndicators: false) {
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
                .padding(.bottom, 12)
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
                    .stroke(
                        LinearGradient(
                            colors: [stepIconColor.opacity(0.4), stepIconColor.opacity(0.1)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 54, height: 54)
                    .blur(radius: 2)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [stepIconColor.opacity(0.18), stepIconColor.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)

                Image(systemName: stepIcon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(stepIconColor)
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

    private var stepIconColor: Color {
        accentColor
    }

    private var stepIcon: String {
        ["waveform.circle.fill", "lock.shield", "cpu", "key.fill", "checkmark.seal.fill"][currentStep]
    }

    private var stepTitle: String {
        switch currentStep {
        case 0: return "WhisperKiller"
        case 1: return L.tr("Permissions", "Разрешения")
        case 2: return L.tr("Engine", "Движок")
        case 3: return "API Key"
        case 4: return L.tr("All Set!", "Всё готово!")
        default: return ""
        }
    }

    private var stepSubtitle: String {
        switch currentStep {
        case 0:
            return L.tr("AI voice-to-text, built natively for macOS", "Голос в текст с AI для macOS")
        case 1:
            return L.tr("Two quick permissions to enable", "Нужно выдать два разрешения")
        case 2:
            return L.tr("Cloud or local — your choice", "Облако или локально — на ваш выбор")
        case 3:
            return L.tr("For cloud transcription & AI modes", "Для облачной транскрибации и AI-режимов")
        case 4:
            return L.tr("WhisperKiller is ready. Good luck!", "WhisperKiller готов к работе. Удачи!")
        default:
            return ""
        }
    }

    // ═══════════════════════════════════════════════
    // MARK: – Progress bar
    // ═══════════════════════════════════════════════

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 4)

                // Fill
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accentColor, accentColor.opacity(0.8)],
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
                            .fill(step <= currentStep ? accentColor : Color.primary.opacity(0.15))
                            .frame(width: 8, height: 8)
                            .overlay(
                                Circle()
                                    .fill(step == currentStep ? accentColor : .clear)
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
            featureCard(
                icon: "mic.fill",
                color: .red,
                title: L.tr("\(appState.settings.hotkeyConfig.displayString) to record", "\(appState.settings.hotkeyConfig.displayString) для записи"),
                desc: L.tr("Hold, Toggle, or Push-to-Talk — pick your style", "Удержание, toggle или push-to-talk — выберите свой режим")
            )
            featureCard(
                icon: "waveform",
                color: accentColor,
                title: L.tr("AI transcription", "AI-транскрибация"),
                desc: L.tr("Cloud (OpenAI) or Local (whisper.cpp with GPU/NPU)", "Облако (OpenAI) или локально (whisper.cpp с GPU/NPU)")
            )
            featureCard(
                icon: "sparkles",
                color: Color.purple,
                title: L.tr("Smart post-processing", "Умная постобработка"),
                desc: L.tr("Dictation · Email · Code · Notes — or create your own", "Dictation · Email · Code · Notes — или создайте свой режим")
            )
            featureCard(
                icon: "keyboard",
                color: .orange,
                title: L.tr("Auto-paste anywhere", "Автовставка куда угодно"),
                desc: L.tr("Result instantly typed into whichever app is focused", "Результат сразу печатается в активное приложение")
            )
        }
    }

    private func featureCard(icon: String, color: Color, title: String, desc: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
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
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(subtleBorder, lineWidth: 1)
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
                .foregroundStyle(accentColor)
            }
            .buttonStyle(.swPlainInteractive)
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
                    Text(L.tr("To ensure permissions like Accessibility and Microphone work correctly, please move WhisperKiller to your Applications folder.", "Чтобы разрешения вроде Accessibility и Microphone работали корректно, переместите WhisperKiller в папку Applications."))
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
                    .buttonStyle(.swPlainInteractive)
                }
                .padding(14)
                .background(Color.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.red.opacity(0.2), lineWidth: 1))
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
                    .buttonStyle(.swPlainInteractive)
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
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(granted ? Color.accentColor.opacity(0.2) : subtleBorder, lineWidth: 1)
        )
    }

    private func permissionTile(icon: String, title: String, subtitle: String, draggable: Bool) -> some View {
        let tile = HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(draggable ? accentColor : textSecondary)
                .frame(width: 22, height: 22)
                .background((draggable ? accentColor : textSecondary).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

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
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(subtleBorder, lineWidth: 1))

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
            TranscriptionEnginePicker(
                selection: $selectedEngine,
                presentation: .setupGrid,
                isReady: isEngineReady
            )

            // Engine details
            if selectedEngine == .cloud {
                cloudEngineCard
            } else if selectedEngine == .local {
                localEngineCard
            } else if selectedEngine == .qwenASR {
                qwenEngineCard
            } else {
                parakeetEngineCard
            }
        }
    }

    private func isEngineReady(_ type: TranscriptionEngineType) -> Bool {
        switch type {
        case .cloud:
            return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .local:
            return whisperInstalled && modelManager.isModelDownloaded(selectedModel)
        case .qwenASR:
            return dependencyInstaller.isQwenASRRuntimeInstalled && modelManager.isQwenModelDownloaded(selectedQwenModel)
        case .parakeet:
            return parakeetModelManager.isModelInstalled
        }
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
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(subtleBorder, lineWidth: 1))
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
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(subtleBorder, lineWidth: 1))
    }

    private var parakeetEngineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: TranscriptionEngineType.parakeet.icon)
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 11))
                Text(L.tr("Fast · Core ML · Offline", "Быстро · Core ML · Офлайн"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(textSecondary)
            }

            tagRow(items: [
                ("waveform", "Parakeet TDT v3", Color.accentColor),
                ("memorychip", L.tr("Apple Silicon", "Apple Silicon"), textSecondary),
                ("arrow.down.circle", L.tr("~460 MB download", "Загрузка ~460 МБ"), textSecondary),
            ])

            Divider()

            parakeetStatusRow

            Text(L.tr(
                "Runs 100% on Apple Silicon Neural Engine. Instant transcription with zero cloud latency.",
                "Работает на Apple Silicon Neural Engine. Мгновенная транскрибация без облачной задержки."
            ))
            .font(.system(size: 11))
            .foregroundStyle(textSecondary)
        }
        .padding(16)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(subtleBorder, lineWidth: 1))
    }

    @ViewBuilder
    private var parakeetStatusRow: some View {
        if !ParakeetTranscriber.isAppleSilicon {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                Text(L.tr("Requires Apple Silicon (M1/M2/M3/M4)", "Требуется Apple Silicon (M1/M2/M3/M4)"))
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }
            .padding(10)
            .background(Color.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            HStack(spacing: 10) {
                switch parakeetModelManager.state {
                case .ready, .installed:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L.tr("Parakeet TDT v3 ready", "Parakeet TDT v3 готова к работе"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(textPrimary)
                        Text(L.tr("Model is cached locally.", "Модель сохранена локально."))
                            .font(.system(size: 10))
                            .foregroundStyle(textSecondary)
                    }
                    Spacer()
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.accentColor)

                case .downloading(let progress, let stage):
                    ProgressView()
                        .controlSize(.small)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(stageTitle(stage)) · \(Int(progress * 100))%")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(textPrimary)
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .frame(maxWidth: 160)
                    }
                    Spacer()
                    Button {
                        parakeetModelManager.cancelDownload()
                    } label: {
                        Text(L.tr("Cancel", "Отмена"))
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.08))
                            .foregroundStyle(textPrimary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.swPlainInteractive)

                case .partial:
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L.tr("Download incomplete", "Скачивание не завершено"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text(L.tr("Retry continues the download", "Повторение продолжит загрузку"))
                            .font(.system(size: 10))
                            .foregroundStyle(textSecondary)
                    }
                    Spacer()
                    Button {
                        parakeetModelManager.download()
                    } label: {
                        Text(L.tr("Retry", "Повторить"))
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(accentColor)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.swPlainInteractive)

                case .validating:
                    ProgressView()
                        .controlSize(.small)
                    Text(L.tr("Checking model…", "Проверяю модель…"))
                        .font(.system(size: 12))
                        .foregroundStyle(textSecondary)
                    Spacer()

                case .failed(let message):
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L.tr("Model error", "Ошибка модели"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.red)
                        Text(message)
                            .font(.system(size: 10))
                            .foregroundStyle(textSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        parakeetModelManager.download(force: true)
                    } label: {
                        Text(L.tr("Repair", "Исправить"))
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(accentColor)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.swPlainInteractive)

                case .notInstalled, .deleting:
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L.tr("Model not downloaded", "Модель не скачана"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(textPrimary)
                        Text(L.tr("~460 MB download", "~460 МБ загрузка"))
                            .font(.system(size: 10))
                            .foregroundStyle(textSecondary)
                    }
                    Spacer()
                    Button {
                        parakeetModelManager.download()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text(L.tr("Download", "Скачать"))
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(accentColor)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.swPlainInteractive)
                }
            }
            .padding(10)
            .background(parakeetRowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var parakeetRowBackground: Color {
        switch parakeetModelManager.state {
        case .ready, .installed:
            return Color.accentColor.opacity(0.08)
        case .failed:
            return Color.red.opacity(0.08)
        case .partial:
            return Color.orange.opacity(0.08)
        default:
            return Color.primary.opacity(0.04)
        }
    }

    private func stageTitle(_ stage: ParakeetDownloadStage) -> String {
        switch stage {
        case .listing: return L.tr("Preparing", "Подготовка")
        case .downloading: return L.tr("Downloading", "Скачивание")
        case .compiling: return L.tr("Compiling", "Компиляция")
        }
    }

    private var qwenEngineCard: some View {
        let runtimeReady = dependencyInstaller.isQwenASRRuntimeInstalled

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 11))
                Text(L.tr("Private · Apple MLX · On-device", "Приватно · Apple MLX · На устройстве"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(textSecondary)
            }

            // Runtime row
            HStack(spacing: 10) {
                Image(systemName: runtimeReady ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(runtimeReady ? Color.accentColor : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(runtimeReady
                        ? L.tr("Qwen3-ASR runtime ready", "Runtime Qwen3-ASR готов")
                        : (dependencyInstaller.isInstallingQwenASR
                            ? L.tr("Installing runtime...", "Устанавливаю runtime...")
                            : L.tr("Runtime not installed", "Runtime не установлен"))
                    )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(runtimeReady ? Color.accentColor : textPrimary)

                    if !runtimeReady && !dependencyInstaller.qwenASRStatus.isEmpty {
                        Text(dependencyInstaller.qwenASRStatus)
                            .font(.system(size: 10))
                            .foregroundStyle(textSecondary)
                    }
                }
                Spacer()

                if dependencyInstaller.isInstallingQwenASR || dependencyInstaller.isCheckingQwenASRRuntime {
                    ProgressView().controlSize(.mini)
                } else if !runtimeReady {
                    Button {
                        dependencyInstaller.installQwenASRRuntime()
                    } label: {
                        Text(L.tr("Install", "Установить"))
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(accentColor)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.swPlainInteractive)
                    .disabled(!QwenASRTranscriber.isAppleSilicon)
                }
            }
            .padding(10)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            // Models section
            VStack(alignment: .leading, spacing: 8) {
                Text(L.tr("MODELS", "МОДЕЛИ"))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(textSecondary)

                ForEach(QwenASRModel.allCases, id: \.self) { model in
                    qwenModelRow(model, runtimeReady: runtimeReady)
                }
            }

            Text(L.tr("Runs fully on this Mac with Apple MLX. No cloud connection needed.", "Работает полностью на этом Mac через Apple MLX. Подключение к сети не требуется."))
                .font(.system(size: 11))
                .foregroundStyle(textSecondary)
        }
        .padding(16)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(subtleBorder, lineWidth: 1))
    }

    private func qwenModelRow(_ model: QwenASRModel, runtimeReady: Bool) -> some View {
        let isCurrent = selectedQwenModel == model
        let isDownloaded = modelManager.isQwenModelDownloaded(model)
        let isPartial = modelManager.hasPartialQwenModelDownload(model)
        let isDownloading = dependencyInstaller.downloadingQwenASRModel == model
        let isRecommended = model == QwenASRModel.recommended

        return HStack(spacing: 10) {
            Image(systemName: isCurrent ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 14))
                .foregroundStyle(isCurrent ? accentColor : textSecondary)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.localizedTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(textPrimary)
                    if isRecommended {
                        Text(L.tr("REC", "РЕК"))
                            .font(.system(size: 8, weight: .heavy, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(accentColor.opacity(0.15))
                            .foregroundStyle(accentColor)
                            .clipShape(Capsule())
                    }
                }
                Text(model.sizeDescription)
                    .font(.system(size: 10))
                    .foregroundStyle(textSecondary)
            }

            Spacer()

            if isDownloaded {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.system(size: 14))
                    Text(L.tr("Ready", "Готово"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
            } else if isDownloading {
                VStack(alignment: .trailing, spacing: 3) {
                    ProgressView(value: Double(dependencyInstaller.qwenASRModelDownloadProgress))
                        .progressViewStyle(.linear)
                        .frame(width: 80)
                    Text("\(Int(dependencyInstaller.qwenASRModelDownloadProgress * 100))%")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(textSecondary)
                }
            } else if isPartial {
                Button {
                    modelManager.deleteQwenModel(model)
                    dependencyInstaller.downloadQwenASRModel(model, modelManager: modelManager) {
                        selectedQwenModel = model
                    }
                } label: {
                    Text(L.tr("Retry", "Повторить"))
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.15))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
                .buttonStyle(.swPlainInteractive)
            } else {
                Button {
                    dependencyInstaller.downloadQwenASRModel(model, modelManager: modelManager) {
                        selectedQwenModel = model
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text(L.tr("Get", "Скачать"))
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(accentColor.opacity(0.14))
                    .foregroundStyle(accentColor)
                    .clipShape(Capsule())
                }
                .buttonStyle(.swPlainInteractive)
                .disabled(!runtimeReady || dependencyInstaller.downloadingQwenASRModel != nil)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(isCurrent ? accentColor.opacity(0.08) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .swInteractiveHover()
        .onTapGesture {
            selectedQwenModel = model
        }
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
                            .background(accentColor.opacity(0.14))
                            .foregroundStyle(accentColor)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.swPlainInteractive)
                } else {
                    Button {
                        installHomebrew()
                    } label: {
                        Text(L.tr("Install", "Установить"))
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(accentColor.opacity(0.14))
                            .foregroundStyle(accentColor)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.swPlainInteractive)
                }
            }
        }
        .padding(10)
        .background(homebrewInstalled ? Color.accentColor.opacity(0.08) : Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                            .background(accentColor.opacity(0.14))
                            .foregroundStyle(accentColor)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.swPlainInteractive)
                }
            }
        }
        .padding(10)
        .background(whisperInstalled ? Color.accentColor.opacity(0.08) : Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                .foregroundStyle(isCurrent ? accentColor : textSecondary)

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
                            .background(accentColor.opacity(0.15))
                            .foregroundStyle(accentColor)
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
                            .buttonStyle(.swPlainInteractive)
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
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(accentColor.opacity(0.14))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.swPlainInteractive)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(isCurrent ? accentColor.opacity(0.08) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .swInteractiveHover()
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
                    Image(systemName: "info.circle.fill").foregroundStyle(accentColor)
                    Text(L.tr("Optional for local engines. Only needed for AI post-processing modes.", "Необязательно для локальных движков. Нужно только для AI-режимов постобработки."))
                        .font(.system(size: 12)).foregroundStyle(textSecondary)
                }
                .padding(14)
                .background(accentColor.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(accentColor.opacity(0.2), lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(L.tr("OpenAI API Key", "OpenAI API Key"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(textPrimary)

                HStack(spacing: 8) {
                    MaskedAPIKeyField(
                        apiKey: $apiKey,
                        presentation: .setupCard,
                        onChanged: {
                            apiValidationState = .idle
                        }
                    )

                    Button {
                        testAPI()
                    } label: {
                        Group {
                            if apiValidationState == .checking {
                                ProgressView().controlSize(.mini).tint(accentColor)
                            } else {
                                Text(L.tr("Test", "Проверить"))
                                    .font(.system(size: 12, weight: .semibold))
                            }
                        }
                        .frame(width: 50)
                        .padding(.vertical, 10)
                        .background(accentColor.opacity(0.14))
                        .foregroundStyle(accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.swPlainInteractive)
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
                    .foregroundStyle(accentColor)
                }
            }
            .padding(16)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(subtleBorder, lineWidth: 1))

            if selectedEngine == .cloud && apiKey.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(L.tr("Cloud engine requires an API key", "Для облачного движка нужен API key"))
                        .font(.system(size: 12)).foregroundStyle(.orange)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    // ═══════════════════════════════════════════════
    // MARK: – Step 4: Ready (Final Slide)
    // ═══════════════════════════════════════════════

    private var readyStep: some View {
        VStack(spacing: 0) {
            // Hotkey row
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(accentColor.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: "keyboard")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(L.tr("Record shortcut", "Горячая клавиша"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(textPrimary)
                    Text(L.tr("Hold or press in any app to dictate", "Нажмите в любом приложении для записи"))
                        .font(.system(size: 11))
                        .foregroundStyle(textSecondary)
                }

                Spacer()

                Text(appState.settings.hotkeyConfig.displayString)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .foregroundStyle(textPrimary)
            }
            .padding(14)

            Divider()
                .padding(.horizontal, 14)
                .opacity(0.1)

            // GitHub Star row
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.yellow.opacity(0.14))
                        .frame(width: 32, height: 32)
                    Image(systemName: "star.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.yellow)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(L.tr("Star on GitHub ⭐", "Пж, поставь звезду на GitHub ⭐"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(textPrimary)
                    Text(L.tr("Free & open source project", "Бесплатный проект с открытым кодом"))
                        .font(.system(size: 11))
                        .foregroundStyle(textSecondary)
                }

                Spacer()

                Button {
                    if let url = URL(string: "https://github.com/iddictive/Whisper-Killer") {
                        NSWorkspace.shared.open(url)
                        hasStarredGitHub = true
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: hasStarredGitHub ? "star.fill" : "star")
                            .font(.system(size: 11, weight: .semibold))
                        Text(hasStarredGitHub
                            ? L.tr("Thank you! ❤️", "Спасибо! ❤️")
                            : L.tr("Star on GitHub", "Поставить звезду")
                        )
                        .font(.system(size: 12, weight: .medium))
                        if !hasStarredGitHub {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9, weight: .bold))
                        }
                    }
                    .foregroundStyle(hasStarredGitHub ? accentColor : textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                }
                .buttonStyle(.swPlainInteractive)
            }
            .padding(14)
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(subtleBorder, lineWidth: 1)
        )
    }


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
                    .buttonStyle(.swPlainInteractive)
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
                        .background(accentColor)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.swPlainInteractive)
                } else {
                    Button {
                        finishSetup()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                            Text(L.tr("Launch WhisperKiller", "Запустить WhisperKiller"))
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: [Color.green, Color.green.opacity(0.85)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.swPlainInteractive)
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
        appState.settings.qwenASRModel = selectedQwenModel

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
