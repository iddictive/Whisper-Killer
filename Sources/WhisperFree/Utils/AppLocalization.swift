import Foundation

enum L {
    static var isRussianSystem: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("ru") == true
    }

    static func tr(_ english: String, _ russian: String) -> String {
        isRussianSystem ? russian : english
    }

    static func languageName(code: String, fallback: String) -> String {
        guard isRussianSystem else { return fallback }

        switch code {
        case "auto": return "Авто"
        case "en": return "Английский"
        case "ru": return "Русский"
        case "es": return "Испанский"
        case "fr": return "Французский"
        case "de": return "Немецкий"
        case "it": return "Итальянский"
        case "pt": return "Португальский"
        case "ja": return "Японский"
        case "ko": return "Корейский"
        case "zh": return "Китайский"
        case "ar": return "Арабский"
        case "hi": return "Хинди"
        case "tr": return "Турецкий"
        case "pl": return "Польский"
        case "nl": return "Нидерландский"
        case "sv": return "Шведский"
        case "uk": return "Украинский"
        default: return fallback
        }
    }

    static func historyCount(entries: Int, files: Int) -> String {
        guard isRussianSystem else {
            return "\(entries) entries" + (files > 0 ? " + \(files) files" : "")
        }

        return "\(entries) \(russianPlural(entries, one: "запись", few: "записи", many: "записей"))"
            + (files > 0 ? " + \(files) \(russianPlural(files, one: "файл", few: "файла", many: "файлов"))" : "")
    }

    static func russianPlural(_ count: Int, one: String, few: String, many: String) -> String {
        let mod10 = count % 10
        let mod100 = count % 100

        if mod10 == 1 && mod100 != 11 { return one }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return few }
        return many
    }
}

extension TranscriptionMode {
    var localizedName: String {
        switch name {
        case "Raw": return L.tr("Raw", "Сырой")
        case "Dictation": return L.tr("Dictation", "Диктовка")
        case "Email": return L.tr("Email", "Письмо")
        case "Code": return L.tr("Code", "Код")
        case "Notes": return L.tr("Notes", "Заметки")
        case "User Story": return L.tr("User Story", "User Story")
        default: return name
        }
    }

    var localizedDescription: String {
        switch name {
        case "Raw":
            return L.tr("Exact transcription without any changes or formatting.", "Точная расшифровка без изменений и форматирования.")
        case "Dictation":
            return L.tr("Fixes grammar and removes filler words while keeping the exact original meaning.", "Исправляет грамматику и убирает слова-паразиты, сохраняя исходный смысл.")
        case "Email":
            return L.tr("Formats speech into a professional email with greetings and a clear structure.", "Оформляет речь в профессиональное письмо с приветствием и понятной структурой.")
        case "Code":
            return L.tr("Converts ideas into clean code comments or technical documentation.", "Преобразует идеи в аккуратные комментарии к коду или техническую документацию.")
        case "Notes":
            return L.tr("Extracts key points and organizes them into a clean markdown list.", "Выделяет главное и собирает это в аккуратный markdown-список.")
        case "User Story":
            return L.tr("Turns spoken product thoughts into structured user stories with acceptance criteria.", "Преобразует голосовые продуктовые мысли в структурированные user story с критериями приёмки.")
        default:
            return description
        }
    }
}

extension RecordingMode {
    var localizedTitle: String {
        switch self {
        case .hold: return L.tr("Hold to Record", "Удерживать для записи")
        case .toggle: return L.tr("Toggle", "Переключатель")
        case .pushToTalk: return L.tr("Push to Talk", "Нажми и говори")
        }
    }

    var localizedDescription: String {
        localizedDescription(hotkey: HotkeyConfig().displayString)
    }

    func localizedDescription(hotkey: String) -> String {
        switch self {
        case .hold:
            return L.tr("Hold \(hotkey) to record, release to transcribe", "Удерживайте \(hotkey) для записи, отпустите для транскрибации")
        case .toggle:
            return L.tr("Press \(hotkey) to start, press again to stop", "Нажмите \(hotkey) для старта, нажмите ещё раз для остановки")
        case .pushToTalk:
            return L.tr("Hold \(hotkey) for push-to-talk", "Удерживайте \(hotkey) для push-to-talk")
        }
    }
}

extension AppPresenceMode {
    var localizedTitle: String {
        switch self {
        case .menuBarOnly:
            return L.tr("Menu Bar Only", "Только menu bar")
        case .dockAndMenuBar:
            return L.tr("Dock + Menu Bar", "Dock + menu bar")
        case .dockOnly:
            return L.tr("Dock Only", "Только Dock")
        }
    }
}

extension InsertionMethod {
    var localizedTitle: String {
        switch self {
        case .paste: return L.tr("Single Block (Clipboard)", "Одним блоком (через буфер)")
        case .type: return L.tr("Incremental (Typing)", "Постепенно (печатью)")
        }
    }

    var localizedDescription: String {
        switch self {
        case .paste:
            return L.tr("Inserts the entire text at once using the clipboard. Reliable and supports a single 'Undo' (Ctrl+Z) step.", "Вставляет весь текст сразу через буфер обмена. Надёжно и поддерживает один шаг отмены.")
        case .type:
            return L.tr("Simulates typing character by character. Avoids touching the clipboard, but creates many 'Undo' steps.", "Имитирует печать символ за символом. Не трогает буфер обмена, но создаёт много шагов отмены.")
        }
    }
}

extension TranscriptionEngineType {
    var localizedTitle: String {
        switch self {
        case .cloud: return L.tr("Cloud (OpenAI)", "Облако (OpenAI)")
        case .local: return L.tr("Local (whisper.cpp)", "Локально (whisper.cpp)")
        case .qwenASR: return L.tr("Local (Qwen3-ASR MLX)", "Локально (Qwen3-ASR MLX)")
        case .gigaAM: return L.tr("GigaAM Russian", "GigaAM русский")
        }
    }

    var localizedShortTitle: String {
        switch self {
        case .cloud: return L.tr("Cloud", "Облако")
        case .local: return L.tr("Local", "Локально")
        case .qwenASR: return "Qwen3-ASR"
        case .gigaAM: return "GigaAM"
        }
    }
}

extension QwenASRModel {
    var localizedTitle: String {
        switch self {
        case .fast: return L.tr("Fast", "Быстро")
        case .quality: return L.tr("Quality", "Качество")
        }
    }
}

extension CloudTranscriptionModel {
    var localizedTitle: String {
        switch self {
        case .whisper1:
            return "Whisper-1"
        case .gpt4oMiniTranscribe:
            return "GPT-4o Mini Transcribe"
        case .gpt4oTranscribe:
            return "GPT-4o Transcribe"
        case .gpt4oTranscribeDiarize:
            return "GPT-4o Transcribe Diarize"
        default:
            return rawValue
        }
    }

    var localizedDescription: String {
        switch self {
        case .whisper1:
            return L.tr("Stable Whisper API model with simple per-minute pricing.", "Стабильная Whisper API-модель с простой поминутной ценой.")
        case .gpt4oMiniTranscribe:
            return L.tr("Newer speech-to-text model with better recognition than Whisper-1 at lower cost than full GPT-4o Transcribe.", "Новая speech-to-text модель с лучшим распознаванием, чем у Whisper-1, и более низкой ценой, чем у полного GPT-4o Transcribe.")
        case .gpt4oTranscribe:
            return L.tr("Highest accuracy OpenAI transcription model in this app.", "Самая точная OpenAI-модель транскрибации в этом приложении.")
        case .gpt4oTranscribeDiarize:
            return L.tr("OpenAI transcription model with native speaker diarization.", "OpenAI-модель транскрибации с нативной диаризацией спикеров.")
        default:
            return L.tr(
                "OpenAI transcription model available to this API key. Cost estimate is unavailable.",
                "OpenAI-модель транскрибации, доступная этому API-ключу. Оценка стоимости недоступна."
            )
        }
    }
}

extension AudioRetentionPolicy {
    var localizedTitle: String {
        switch self {
        case .oneDay: return L.tr("1 Day", "1 день")
        case .sevenDays: return L.tr("7 Days", "7 дней")
        case .thirtyDays: return L.tr("30 Days", "30 дней")
        case .ninetyDays: return L.tr("90 Days", "90 дней")
        case .forever: return L.tr("Forever", "Всегда")
        }
    }
}
