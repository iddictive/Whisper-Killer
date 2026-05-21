import Foundation

struct AIChatResponse {
    let text: String
    let promptTokens: Int
    let completionTokens: Int
}

enum AIChatService {
    static func fetchOpenAIChatModels(apiKey: String) async throws -> [String] {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw TranscriptionError.noAPIKey }

        let url = URL(string: "https://api.openai.com/v1/models")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw TranscriptionError.networkError("Invalid OpenAI API key.")
        }

        guard httpResponse.statusCode == 200 else {
            let errorText = openAIErrorMessage(from: data) ?? "HTTP \(httpResponse.statusCode)"
            throw TranscriptionError.networkError("OpenAI model list failed: \(errorText)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]]
        else {
            throw TranscriptionError.invalidResponse
        }

        return dataArray
            .compactMap { $0["id"] as? String }
            .filter(isLikelyChatModel)
            .sorted { lhs, rhs in
                modelSortScore(lhs) == modelSortScore(rhs)
                    ? lhs.localizedStandardCompare(rhs) == .orderedAscending
                    : modelSortScore(lhs) < modelSortScore(rhs)
            }
    }

    static func send(
        messages: [AIChatMessage],
        model: String,
        apiKey: String
    ) async throws -> AIChatResponse {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw TranscriptionError.noAPIKey }
        guard !trimmedModel.isEmpty else {
            throw TranscriptionError.networkError("Select an OpenAI chat model first.")
        }

        let url = URL(string: "https://api.openai.com/v1/responses")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let apiMessages = messages.suffix(24).map { message -> [String: Any] in
            [
                "role": message.role == .assistant ? "assistant" : "user",
                "content": message.content
            ]
        }

        let payload: [String: Any] = [
            "model": trimmedModel,
            "instructions": "You are a concise assistant for transcript analysis, summaries, translations, and follow-up questions. Use only attached context when the user asks about attached material.",
            "input": apiMessages
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, httpResponse) = try await TransientHTTPRetry.data(for: request, label: "AI chat")

        if httpResponse.statusCode == 401 {
            throw TranscriptionError.networkError("Invalid OpenAI API key.")
        }

        guard httpResponse.statusCode == 200 else {
            let errorText = openAIErrorMessage(from: data) ?? String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TranscriptionError.networkError("AI chat failed: \(errorText)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = responseText(from: json) else {
            throw TranscriptionError.invalidResponse
        }

        let usage = json["usage"] as? [String: Any]
        let promptTokens = usage?["input_tokens"] as? Int ?? usage?["prompt_tokens"] as? Int ?? 0
        let completionTokens = usage?["output_tokens"] as? Int ?? usage?["completion_tokens"] as? Int ?? 0
        return AIChatResponse(
            text: content.trimmingCharacters(in: .whitespacesAndNewlines),
            promptTokens: promptTokens,
            completionTokens: completionTokens
        )
    }

    private static func isLikelyChatModel(_ id: String) -> Bool {
        let value = id.lowercased()
        guard value.hasPrefix("gpt-") || value.hasPrefix("o") || value.hasPrefix("chatgpt-") else {
            return false
        }
        return !value.contains("transcribe")
            && !value.contains("whisper")
            && !value.contains("tts")
            && !value.contains("audio")
            && !value.contains("image")
            && !value.contains("embedding")
            && !value.contains("realtime")
    }

    private static func modelSortScore(_ id: String) -> Int {
        let value = id.lowercased()
        if value.contains("mini") { return 0 }
        if value.hasPrefix("gpt-4") { return 1 }
        if value.hasPrefix("o") { return 2 }
        return 3
    }

    private static func responseText(from json: [String: Any]) -> String? {
        if let outputText = json["output_text"] as? String, !outputText.isEmpty {
            return outputText
        }

        guard let output = json["output"] as? [[String: Any]] else { return nil }
        let parts = output.compactMap { item -> String? in
            guard let content = item["content"] as? [[String: Any]] else { return nil }
            return content.compactMap { part in
                part["text"] as? String
            }.joined()
        }

        let text = parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func openAIErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return nil
        }
        return message
    }
}
