import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var dependencyInstaller = DependencyInstaller.shared

    private let popoverMinWidth: CGFloat = 420
    private let popoverIdealWidth: CGFloat = 450
    private let popoverMaxWidth: CGFloat = 520

    private var selectedInputDeviceName: String {
        appState.availableInputDevices.first(where: { $0.uniqueID == appState.settings.selectedInputDeviceID })?.localizedName
            ?? L.tr("Default", "По умолчанию")
    }

    var body: some View {
        VStack(spacing: 0) {
            mainContent
        }
        .frame(
            minWidth: popoverMinWidth,
            idealWidth: popoverIdealWidth,
            maxWidth: popoverMaxWidth,
            alignment: .top
        )
        .fixedSize(horizontal: false, vertical: true)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow).ignoresSafeArea())
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            // ─── Accessibility Warning ─────────────
            if !appState.isHotkeyTrusted {
                Button {
                    appState.requestAccessibilityPermission()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(SW.warning)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(L.tr("Accessibility access needed", "Нужен Accessibility"))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(SW.primaryText)
                                .lineLimit(1)
                            Text(L.tr("Open Settings", "Открыть настройки"))
                                .font(.system(size: 10))
                                .foregroundStyle(SW.secondaryText)
                                .lineLimit(1)
                        }
                        .layoutPriority(1)
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(SW.secondaryText)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: SW.radiusMedium, style: .continuous).fill(SW.warning.opacity(0.12)))
                    .overlay(RoundedRectangle(cornerRadius: SW.radiusMedium, style: .continuous).strokeBorder(SW.warning.opacity(0.24), lineWidth: 1))
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                }
                .buttonStyle(.plain)
            }

            headerControls
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            modeToolbar
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            // ─── Last Transcription ─────────────
            if let lastText = appState.lastTranscription {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text(L.tr("LAST TRANSCRIPTION", "ПОСЛЕДНЯЯ ТРАНСКРИПЦИЯ"))
                        .font(SW.labelFont)
                        .foregroundStyle(.secondary)

                    Text(lastText)
                        .font(SW.compactFont)
                        .lineLimit(4)
                        .foregroundStyle(.primary)

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(lastText, forType: .string)
                        appState.copiedFeedback = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            appState.copiedFeedback = false
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: appState.copiedFeedback ? "checkmark" : "doc.on.doc.fill")
                                .font(.system(size: 12, weight: .semibold))
                            Text(appState.copiedFeedback ? L.tr("Copied", "Скопировано") : L.tr("Copy", "Копировать"))
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .foregroundStyle(.white)
                        .background(
                            RoundedRectangle(cornerRadius: SW.radiusMedium, style: .continuous)
                                .fill(appState.copiedFeedback ? SW.accent.opacity(0.3) : SW.accent)
                        )
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.2), value: appState.copiedFeedback)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            // ─── Error ──────────────────────────
            if let error = appState.lastError {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .lineLimit(2)

                        if isMissingWhisperCppError {
                            if !dependencyInstaller.isHomebrewInstalled {
                                Text(dependencyInstaller.homebrewStatus.isEmpty ? L.tr("Homebrew required", "Сначала нужен Homebrew") : dependencyInstaller.homebrewStatus)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.orange.opacity(0.85))
                                    .lineLimit(2)
                            } else if dependencyInstaller.isInstallingWhisperCpp {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.mini)
                                    Text(L.tr("Installing whisper-cpp…", "Устанавливаю whisper-cpp…"))
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.orange)
                                }
                            } else if !dependencyInstaller.whisperCppStatus.isEmpty {
                                Text(dependencyInstaller.whisperCppStatus)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.orange.opacity(0.85))
                                    .lineLimit(2)
                            }
                        }
                    }

                    Spacer()

                    if isMissingWhisperCppError {
                        Button {
                            if dependencyInstaller.isHomebrewInstalled {
                                dependencyInstaller.installWhisperCpp {
                                    if dependencyInstaller.isWhisperCppInstalled {
                                        appState.clearError()
                                    }
                                }
                            } else {
                                dependencyInstaller.installHomebrew()
                            }
                        } label: {
                            Text(dependencyInstaller.isHomebrewInstalled ? L.tr("Install", "Установить") : L.tr("Install Brew", "Установить Brew"))
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .buttonStyle(.borderless)
                        .disabled(dependencyInstaller.isInstallingWhisperCpp || dependencyInstaller.isInstallingHomebrew)
                    }

                    Button {
                        appState.clearError()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.orange.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
                .onTapGesture {
                    if !isMissingWhisperCppError {
                        appState.clearError()
                    }
                }
            }

            Divider()

            // ─── Navigation ─────────────────────
            VStack(spacing: 0) {
                menuButton(icon: "gear", title: L.tr("Settings", "Настройки")) {
                    AppDelegate.shared?.showSettings()
                }
                menuButton(icon: "clock", title: L.tr("History", "История")) {
                    AppDelegate.shared?.showHistory()
                }
                menuButton(icon: "doc.badge.plus", title: L.tr("Transcribe File...", "Транскрибировать файл...")) {
                    AppDelegate.shared?.showFileTranscription()
                }

                menuButton(icon: "wand.and.stars", title: L.tr("Setup Wizard", "Мастер настройки")) {
                    AppDelegate.shared?.showSetupWizard()
                }

                if AppState.liveTranslatorFeatureAvailable && appState.settings.liveTranslatorEnabled {
                    Divider()
                    menuButton(icon: "captions.bubble", title: appState.showLiveTranslatorOverlay ? L.tr("Stop Live Translator", "Остановить Live Translator") : L.tr("Start Live Translator", "Запустить Live Translator")) {
                        appState.toggleLiveTranslator()
                    }
                }

                if AppState.liveTranslatorFeatureAvailable {
                    menuButton(icon: "mic.badge.plus", title: appState.showLiveTranslatorOverlay ? L.tr("Stop Mic -> Russian", "Остановить микрофон -> русский") : L.tr("Start Mic -> Russian", "Запустить микрофон -> русский")) {
                        appState.toggleRussianMicrophoneTranslator()
                    }
                }
            }

            Divider()

            menuButton(icon: "power", title: L.tr("Quit", "Выйти")) {
                NSApplication.shared.terminate(nil)
            }

            Divider()

            menuButton(icon: "arrow.clockwise", title: L.tr("Check for Updates...", "Проверить обновления...")) {
                GitHubUpdater.shared.checkForUpdates(manual: true)
            }
        }
        .frame(
            minWidth: popoverMinWidth,
            idealWidth: popoverIdealWidth,
            maxWidth: .infinity,
            alignment: .top
        )
        .onAppear {
            if !appState.settings.setupCompleted {
                DispatchQueue.main.async {
                    AppDelegate.shared?.showSetupWizard()
                }
            }
        }
    }

    private var headerControls: some View {
        HStack(spacing: 8) {
            inputDeviceMenu
                .frame(maxWidth: 132)
                .layoutPriority(1)

            sourceMenu
                .layoutPriority(1)

            Spacer(minLength: 8)

            recordButton

            if AppState.liveTranslatorFeatureAvailable {
                liveTranslatorButton
            }

            if appState.state == .processing {
                ProgressView().controlSize(.mini)
            }
        }
    }

    private var modeToolbar: some View {
        let activeModeName = appState.settings.isModeEnabled(appState.settings.selectedMode)
            ? appState.settings.selectedModeName
            : TranscriptionMode.raw.name

        return HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(appState.settings.allModes) { mode in
                        let isEnabled = appState.settings.isModeEnabled(mode)
                        let isSelected = activeModeName == mode.name

                        Button {
                            guard isEnabled else { return }
                            appState.settings.selectedModeName = mode.name
                            appState.saveSettings()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: isEnabled ? mode.icon : "lock.fill")
                                    .font(.system(size: 10, weight: .semibold))
                                Text(mode.localizedName)
                                    .font(.system(size: 11, weight: .semibold))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(isSelected ? SW.accent.opacity(0.14) : SW.rowBackground)
                            .foregroundStyle(isSelected ? SW.accent : (isEnabled ? SW.primaryText : SW.secondaryText))
                            .clipShape(RoundedRectangle(cornerRadius: SW.radiusSmall, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: SW.radiusSmall, style: .continuous)
                                    .strokeBorder(isSelected ? SW.accent.opacity(0.32) : SW.border, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!isEnabled)
                        .help(modeHelpText(for: mode, isEnabled: isEnabled))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        }
    }

    private func modeHelpText(for mode: TranscriptionMode, isEnabled: Bool) -> String {
        if isEnabled {
            return mode.localizedDescription
        }

        if !appState.settings.hasOpenAIAPIKey {
            return L.tr("Add an OpenAI API key to unlock AI modes.", "Добавьте OpenAI API key, чтобы открыть AI-режимы.")
        }

        if !appState.settings.enablePostProcessing {
            return L.tr("Enable AI Refinement to unlock this mode.", "Включите AI-обработку, чтобы открыть этот режим.")
        }

        return L.tr("This mode is unavailable.", "Этот режим недоступен.")
    }

    private var sourceMenu: some View {
        Menu {
            ForEach(TranscriptionEngineType.allCases, id: \.self) { type in
                Button {
                    appState.settings.engineType = type
                    if type == .gigaAM {
                        appState.settings.language = "ru"
                    }
                    appState.saveSettings()
                } label: {
                    HStack {
                        Label(type.localizedTitle, systemImage: type.icon)
                        if appState.settings.engineType == type {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: appState.settings.engineType.icon)
                    .font(.system(size: 8))
                Text(appState.settings.engineType.localizedShortTitle)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 6))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(SW.rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: SW.radiusSmall, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var inputDeviceMenu: some View {
        Menu {
            Button {
                appState.settings.selectedInputDeviceID = nil
                appState.saveSettings()
            } label: {
                HStack {
                    Text(L.tr("System Default", "Системный"))
                    if appState.settings.selectedInputDeviceID == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Divider()

            ForEach(appState.availableInputDevices, id: \.uniqueID) { device in
                Button {
                    appState.settings.selectedInputDeviceID = device.uniqueID
                    appState.saveSettings()
                } label: {
                    HStack {
                        Text(device.localizedName)
                        if appState.settings.selectedInputDeviceID == device.uniqueID {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 8))
                Text(selectedInputDeviceName)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down")
                    .font(.system(size: 6))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(SW.rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: SW.radiusSmall, style: .continuous))
        }
        .menuStyle(.borderlessButton)
    }

    private var recordButton: some View {
        Button {
            appState.toggleFromMenuBar()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: appState.state == .recording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 10))
                Text(appState.state == .recording ? L.tr("Stop", "Стоп") : L.tr("Rec", "Rec"))
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundStyle(appState.state == .recording ? .white : .primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .frame(minWidth: 54)
            .background(
                RoundedRectangle(cornerRadius: SW.radiusSmall, style: .continuous)
                    .fill(appState.state == .recording ? SW.danger : SW.rowBackground)
            )
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    private var liveTranslatorButton: some View {
        Button {
            appState.toggleRussianMicrophoneTranslator()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: appState.showLiveTranslatorOverlay ? "stop.circle.fill" : "captions.bubble.fill")
                    .font(.system(size: 10))
                Text(appState.showLiveTranslatorOverlay ? L.tr("Stop RU", "Стоп") : L.tr("Mic -> RU", "RU"))
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundStyle(appState.showLiveTranslatorOverlay ? .white : .primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .frame(minWidth: 50)
            .background(
                RoundedRectangle(cornerRadius: SW.radiusSmall, style: .continuous)
                    .fill(appState.showLiveTranslatorOverlay ? SW.accent : SW.rowBackground)
            )
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    private func menuButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, alignment: .center)
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var isMissingWhisperCppError: Bool {
        appState.lastError?.localizedCaseInsensitiveContains("whisper-cpp not found") == true
    }
}
