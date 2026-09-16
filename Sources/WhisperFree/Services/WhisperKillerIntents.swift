import AppIntents
import Cocoa

@available(macOS 14.0, *)
struct ToggleRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Начать / Остановить запись голоса"
    static var description = IntentDescription("Переключает запись голоса для распознавания речи в текст")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        AppState.shared.toggleRecording()
        return .result()
    }
}

@available(macOS 14.0, *)
struct TranscribeFileIntent: AppIntent {
    static var title: LocalizedStringResource = "Транскрибировать файл"
    static var description = IntentDescription("Открывает окно транскрибации аудио и видео файлов")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppDelegate.shared?.showFileTranscription()
        return .result()
    }
}

@available(macOS 14.0, *)
struct OpenAIChatIntent: AppIntent {
    static var title: LocalizedStringResource = "Открыть AI Чат"
    static var description = IntentDescription("Открывает окно AI Чата с поддержкой голоса")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppDelegate.shared?.showAIChat()
        return .result()
    }
}

@available(macOS 14.0, *)
struct OpenHistoryIntent: AppIntent {
    static var title: LocalizedStringResource = "Открыть историю записей"
    static var description = IntentDescription("Открывает историю ранее сохранённых расшифровок")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppDelegate.shared?.showHistory()
        return .result()
    }
}

@available(macOS 14.0, *)
struct OpenSettingsIntent: AppIntent {
    static var title: LocalizedStringResource = "Настройки WhisperKiller"
    static var description = IntentDescription("Открывает окно настроек WhisperKiller")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppDelegate.shared?.showSettings()
        return .result()
    }
}

@available(macOS 14.0, *)
struct ToggleLiveTranslatorIntent: AppIntent {
    static var title: LocalizedStringResource = "Живой переводчик и субтитры"
    static var description = IntentDescription("Включает или выключает живой переводчик с субтитрами")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        AppState.shared.toggleLiveTranslator()
        return .result()
    }
}

@available(macOS 14.0, *)
struct WhisperKillerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleRecordingIntent(),
            phrases: [
                "Запись голоса в \(.applicationName)",
                "Запустить запись в \(.applicationName)",
                "Остановить запись в \(.applicationName)",
                "Диктовка в \(.applicationName)",
                "Record voice in \(.applicationName)",
                "Start recording in \(.applicationName)",
                "Stop recording in \(.applicationName)"
            ],
            shortTitle: "Запись голоса",
            systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: TranscribeFileIntent(),
            phrases: [
                "Транскрибировать файл в \(.applicationName)",
                "Расшифровать аудио в \(.applicationName)",
                "Transcribe file in \(.applicationName)"
            ],
            shortTitle: "Транскрибация файла",
            systemImageName: "doc.badge.arrow.up"
        )
        AppShortcut(
            intent: OpenAIChatIntent(),
            phrases: [
                "AI Чат в \(.applicationName)",
                "Чат в \(.applicationName)",
                "Open AI Chat in \(.applicationName)"
            ],
            shortTitle: "AI Чат",
            systemImageName: "bubble.left.and.bubble.right.fill"
        )
        AppShortcut(
            intent: OpenHistoryIntent(),
            phrases: [
                "История записей в \(.applicationName)",
                "История в \(.applicationName)",
                "Show history in \(.applicationName)"
            ],
            shortTitle: "История",
            systemImageName: "clock.arrow.circlepath"
        )
        AppShortcut(
            intent: OpenSettingsIntent(),
            phrases: [
                "Настройки \(.applicationName)",
                "Открыть настройки \(.applicationName)",
                "Open \(.applicationName) settings"
            ],
            shortTitle: "Настройки",
            systemImageName: "gear"
        )
        AppShortcut(
            intent: ToggleLiveTranslatorIntent(),
            phrases: [
                "Живой переводчик в \(.applicationName)",
                "Live translator in \(.applicationName)"
            ],
            shortTitle: "Живой переводчик",
            systemImageName: "captions.bubble.fill"
        )
    }
}

