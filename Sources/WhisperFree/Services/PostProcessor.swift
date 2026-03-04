import Foundation

final class PostProcessor {
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func process(text: String, mode: TranscriptionMode) async throws -> String {
        let engine = settings.postProcessingEngine
        let apiKey = (engine == .openai) ? settings.apiKey : settings.perplexityApiKey
        
        guard !apiKey.isEmpty else { return text }
        guard !text.isEmpty else { return text }

        let url: URL
        let model: String
        
        switch engine {
        case .openai:
            url = URL(string: "https://api.openai.com/v1/chat/completions")!
            model = "gpt-4o-mini"
        case .perplexity:
            url = URL(string: "https://api.perplexity.ai/chat/completions")!
            model = "sonar-pro" // High quality reasoning model
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": mode.systemPrompt],
                ["role": "user", "content": text]
            ],
            "temperature": 0.3,
            "max_tokens": 2048
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
            throw TranscriptionError.networkError("Invalid API Key for \(engine.rawValue). Please check your settings.")
        }
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TranscriptionError.networkError("\(engine.rawValue) post-processing failed: \(errorText)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            throw TranscriptionError.invalidResponse
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
