import Cocoa
import CoreSpotlight
import UniformTypeIdentifiers

final class SpotlightIndexManager {
    static let shared = SpotlightIndexManager()

    enum ItemIdentifier: String, CaseIterable {
        case app = "com.whisperkiller.app.spotlight.main"
        case record = "com.whisperkiller.app.spotlight.record"
        case fileTranscription = "com.whisperkiller.app.spotlight.file"
        case liveTranslator = "com.whisperkiller.app.spotlight.livetranslator"
        case aiChat = "com.whisperkiller.app.spotlight.aichat"
        case history = "com.whisperkiller.app.spotlight.history"
        case settings = "com.whisperkiller.app.spotlight.settings"
        case googleMeet = "com.whisperkiller.app.spotlight.googlemeet"
    }

    private let domainIdentifier = "com.whisperkiller.app.features"
    private var isIndexing = false

    func indexItems() {
        guard CSSearchableIndex.isIndexingAvailable() else {
            print("[Spotlight] CoreSpotlight is not available on this system.")
            return
        }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            guard !self.isIndexing else { return }
            self.isIndexing = true
            defer { self.isIndexing = false }

            let items = self.buildSearchableItems()
            CSSearchableIndex.default().indexSearchableItems(items) { error in
                if let error = error {
                    print("[Spotlight] Failed to index items: \(error.localizedDescription)")
                } else {
                    print("[Spotlight] Successfully indexed \(items.count) searchable items for WhisperKiller.")
                }
            }
        }
    }

    func handleActivity(_ userActivity: NSUserActivity, appDelegate: AppDelegate) -> Bool {
        guard userActivity.activityType == CSSearchableItemActionType,
              let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              let item = ItemIdentifier(rawValue: identifier) else {
            return false
        }

        print("[Spotlight] Activated item from search: \(identifier)")
        DispatchQueue.main.async {
            switch item {
            case .app:
                appDelegate.showMainMenu()
            case .record:
                AppState.shared.toggleRecording()
            case .fileTranscription:
                appDelegate.showFileTranscription()
            case .liveTranslator:
                AppState.shared.toggleLiveTranslator()
            case .aiChat:
                appDelegate.showAIChat()
            case .history:
                appDelegate.showHistory()
            case .settings:
                appDelegate.showSettings()
            case .googleMeet:
                appDelegate.showFileTranscription()
                AppState.shared.requestGoogleMeetImport()
            }
        }
        return true
    }

    private func buildSearchableItems() -> [CSSearchableItem] {
        let isRu = L.isRussianSystem
        let iconData = loadThumbnailData()

        var items: [CSSearchableItem] = []

        // 1. Главное приложение / Запись голоса (Main App / Voice Recording)
        items.append(createItem(
            identifier: .app,
            title: isRu ? "WhisperKiller — Запись голоса и распознавание речи" : "WhisperKiller — Voice Recording & Speech-to-Text",
            description: isRu
                ? "Быстрая запись голоса, диктовка и офлайн-транскрибация речи через Whisper на Mac"
                : "Fast voice recording, dictation, and offline speech-to-text via Whisper on Mac",
            keywords: [
                "запись голоса", "запись", "записать голос", "диктофон", "диктовка",
                "диктовать", "распознавание речи", "голос в текст", "транскрибация",
                "транскрибировать", "перевод голоса", "микрофон", "звукозапись",
                "аудиозапись", "виспер", "виспер киллер", "whisper", "whisperkiller",
                "whisper killer", "голосовой ввод", "записать речь", "voice recording",
                "record voice", "voice recorder", "dictation", "speech to text",
                "voice to text", "speech recognition", "transcription", "transcribe",
                "audio recording", "voice input"
            ],
            alternateNames: ["WhisperKiller", "Запись голоса", "Диктофон", "Диктовка", "Voice Recording", "Whisper Killer"],
            thumbnailData: iconData
        ))

        // 2. Начать / Остановить запись голоса (Toggle Voice Recording)
        items.append(createItem(
            identifier: .record,
            title: isRu ? "Начать / Остановить запись голоса (Start Dictation)" : "Start / Stop Voice Recording (Dictation)",
            description: isRu
                ? "Включить микрофон и начать распознавание речи в текст"
                : "Toggle microphone and speech-to-text recording",
            keywords: [
                "начать запись", "запустить запись", "остановить запись", "старт записи",
                "включить диктофон", "запись звука", "голосовая заметка", "быстрая запись",
                "start recording", "stop recording", "record", "voice record",
                "toggle recording", "start dictation", "audio capture"
            ],
            alternateNames: ["Начать запись", "Запись голоса", "Start Recording", "Voice Record"],
            thumbnailData: iconData
        ))

        // 3. Транскрибировать аудио / видео файл (Transcribe File)
        items.append(createItem(
            identifier: .fileTranscription,
            title: isRu ? "Транскрибация файла (Transcribe Audio/Video File)" : "Transcribe Audio or Video File",
            description: isRu
                ? "Распознавание речи из аудио- и видеофайлов (MP3, WAV, M4A, MP4, MOV)"
                : "Speech-to-text transcription from audio and video files (MP3, WAV, M4A, MP4, MOV)",
            keywords: [
                "транскрибировать файл", "расшифровка аудио", "расшифровать видео",
                "аудио в текст", "видео в текст", "mp3 в текст", "субтитры из видео",
                "расшифровка записи", "перевод файла", "transcribe file", "audio to text",
                "video to text", "mp3 to text", "transcribe audio", "transcribe video"
            ],
            alternateNames: ["Транскрибация файла", "Расшифровка аудио", "Transcribe File"],
            thumbnailData: iconData
        ))

        // 4. Живой переводчик и субтитры (Live Translator & Subtitles)
        items.append(createItem(
            identifier: .liveTranslator,
            title: isRu ? "Живой переводчик и субтитры (Live Translator)" : "Live Translator & Subtitle Overlay",
            description: isRu
                ? "Перевод системного звука и микрофона на лету с отображением субтитров на экране"
                : "Real-time translation of system audio and microphone with on-screen subtitles",
            keywords: [
                "живой переводчик", "переводчик", "субтитры", "перевод на лету",
                "синхронный перевод", "перевод видео", "перевод созвона", "титры",
                "live translator", "subtitles", "real-time translation", "live captions",
                "translate audio", "subtitle overlay", "speech translation"
            ],
            alternateNames: ["Живой переводчик", "Субтитры", "Live Translator", "Subtitles"],
            thumbnailData: iconData
        ))

        // 5. AI Чат с голосом (AI Chat with Voice)
        items.append(createItem(
            identifier: .aiChat,
            title: isRu ? "AI Чат с голосовым вводом (AI Chat)" : "AI Chat with Voice",
            description: isRu
                ? "Интеллектуальный помощник с поддержкой голосовых сообщений и текста"
                : "Smart AI assistant with voice input and audio transcription",
            keywords: [
                "ai чат", "чатбот", "голосовой чат", "искусственный интеллект",
                "нейросеть", "чат с ии", "помощник", "ассистент", "ai chat",
                "voice chat", "ai assistant", "chatbot", "gpt", "voice assistant"
            ],
            alternateNames: ["AI Чат", "AI Chat", "Голосовой чат"],
            thumbnailData: iconData
        ))

        // 6. История записей (Transcription History)
        items.append(createItem(
            identifier: .history,
            title: isRu ? "История транскрипций (History)" : "Transcription History",
            description: isRu
                ? "Просмотр, поиск и экспорт всех ранее сохранённых расшифровок речи"
                : "View, search, and export past voice recordings and transcriptions",
            keywords: [
                "история", "история записей", "история транскрипций", "архив записей",
                "сохраненные записи", "заметки голосом", "поиск по записям", "history",
                "transcription history", "past recordings", "saved transcripts", "voice notes"
            ],
            alternateNames: ["История записей", "История", "History"],
            thumbnailData: iconData
        ))

        // 7. Настройки (Settings)
        items.append(createItem(
            identifier: .settings,
            title: isRu ? "Настройки WhisperKiller (Settings)" : "WhisperKiller Settings",
            description: isRu
                ? "Настройка моделей Whisper, горячих клавиш, микрофона и языков"
                : "Configure Whisper models, hotkeys, microphone, and language preferences",
            keywords: [
                "настройки", "параметры", "конфигурация", "горячие клавиши",
                "выбор микрофона", "модели whisper", "язык распознавания",
                "settings", "preferences", "config", "hotkeys", "microphone settings",
                "whisper models", "language"
            ],
            alternateNames: ["Настройки", "Settings", "Preferences"],
            thumbnailData: iconData
        ))

        // 8. Импорт Google Meet (Google Meet Import)
        items.append(createItem(
            identifier: .googleMeet,
            title: isRu ? "Импорт записей Google Meet (Google Meet)" : "Import Google Meet Recording",
            description: isRu
                ? "Загрузка и расшифровка записей встреч Google Meet из Google Drive"
                : "Download and transcribe Google Meet meeting recordings from Google Drive",
            keywords: [
                "google meet", "гугл мит", "запись встречи", "созвон", "митинг",
                "транскрибация мита", "google drive meet", "meet recording",
                "meeting transcription", "transcribe meeting", "google drive"
            ],
            alternateNames: ["Google Meet", "Импорт встреч"],
            thumbnailData: iconData
        ))

        return items
    }

    private func createItem(
        identifier: ItemIdentifier,
        title: String,
        description: String,
        keywords: [String],
        alternateNames: [String],
        thumbnailData: Data?
    ) -> CSSearchableItem {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .content)
        attributeSet.title = title
        attributeSet.displayName = title
        attributeSet.contentDescription = description
        attributeSet.keywords = keywords
        attributeSet.alternateNames = alternateNames
        if let thumbnailData = thumbnailData {
            attributeSet.thumbnailData = thumbnailData
        }

        return CSSearchableItem(
            uniqueIdentifier: identifier.rawValue,
            domainIdentifier: domainIdentifier,
            attributeSet: attributeSet
        )
    }

    private func loadThumbnailData() -> Data? {
        let iconURLs = [
            Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
            Bundle.main.url(forResource: "AppIcon", withExtension: "icns", subdirectory: "Resources"),
            Bundle.main.resourceURL?.appendingPathComponent("Resources/AppIcon.icns")
        ].compactMap { $0 }

        guard let iconURL = iconURLs.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let image = NSImage(contentsOf: iconURL),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            if let appIcon = NSApp.applicationIconImage,
               let tiffData = appIcon.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                return pngData
            }
            return nil
        }
        return pngData
    }
}

