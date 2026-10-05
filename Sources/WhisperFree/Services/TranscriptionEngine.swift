import Foundation
import CoreMedia

// MARK: - Transcription Engine Protocol

protocol TranscriptionEngine {
    func transcribe(audioURL: URL, language: String?, timeRange: CMTimeRange?, onProgress: ((Float, TimeInterval?) -> Void)?) async throws -> String
    func pause()
    func resume()
    func cancel()
}

extension TranscriptionEngine {
    func pause() {}
    func resume() {}
    func cancel() {}
}

enum TranscriptionError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case networkError(String)
    case modelNotDownloaded
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key configured. Please add your cloud provider API key in Settings → Engine & API."
        case .invalidResponse:
            return "Invalid response from transcription service."
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .modelNotDownloaded:
            return "Local model not downloaded. Please download a model in Settings → Engine."
        case .transcriptionFailed(let msg):
            return "Transcription failed: \(msg)"
        }
    }

    var shouldReduceCloudConcurrency: Bool {
        guard case .networkError(let message) = self else { return false }
        let normalized = message.lowercased()

        if normalized.contains("http 429") || normalized.contains("rate limit") || normalized.contains("quota") {
            return true
        }

        for statusCode in [500, 502, 503, 504] where normalized.contains("http \(statusCode)") {
            return true
        }

        return false
    }

    var overlayDescription: String {
        guard case .transcriptionFailed(let details) = self else {
            return localizedDescription
        }
        if details.contains("whisper_init_from_file") && details.contains("failed to open") {
            return L.tr("Local model unavailable. Open Engine & API.", "Модель недоступна. Откройте Engine & API.")
        }
        if details.contains("\n") || details.count > 200 {
            return L.tr("Transcription failed. See History for details.", "Ошибка транскрибации. Подробности в истории.")
        }
        return localizedDescription
    }
}

// MARK: - Engine Factory

struct TranscriptionEngineFactory {
    static func create(for type: TranscriptionEngineType, settings: AppSettings) -> TranscriptionEngine {
        switch type {
        case .cloud:
            return CloudWhisper(apiKey: settings.normalizedAPIKey, model: settings.effectiveCloudTranscriptionModel, configuration: settings.cloudAPIConfiguration)
        case .local:
            return LocalWhisper(modelSize: settings.localModelSize)
        case .qwenASR:
            return QwenASRTranscriber(model: settings.qwenASRModel)
        case .parakeet:
            return ParakeetTranscriber(model: settings.parakeetModel)
        }
    }
}
