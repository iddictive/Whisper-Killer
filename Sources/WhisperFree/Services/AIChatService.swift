import Foundation

struct AIChatResponse {
    let text: String
    let promptTokens: Int
    let completionTokens: Int
}

enum AIChatService {
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

    static func relevantOpenAIChatModels(from ids: [String]) -> [String] {
        let candidates = ids.compactMap { id -> (id: String, generation: GPTGeneration)? in
            guard isLikelyGeneralChatModel(id),
                  let generation = gptGeneration(for: id)
            else {
                return nil
            }
            return (id, generation)
        }

        let recentGenerations = Set(candidates.map(\.generation))
            .sorted(by: >)
            .prefix(3)

        return candidates
            .filter { recentGenerations.contains($0.generation) }
            .sorted { lhs, rhs in
                if lhs.generation != rhs.generation {
                    return lhs.generation > rhs.generation
                }
                return modelVariantScore(lhs.id) == modelVariantScore(rhs.id)
                    ? lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
                    : modelVariantScore(lhs.id) < modelVariantScore(rhs.id)
            }
            .map(\.id)
    }

    private static func isLikelyGeneralChatModel(_ id: String) -> Bool {
        let value = id.lowercased()
        guard value.hasPrefix("gpt-"), !hasSnapshotDate(value) else {
            return false
        }

        let specializedMarkers = [
            "audio", "chat-latest", "codex", "computer-use", "deep-research",
            "embedding", "image", "instruct", "moderation", "realtime",
            "search", "transcribe", "tts", "vision", "whisper"
        ]
        return !specializedMarkers.contains { value.contains($0) }
    }

    private static func hasSnapshotDate(_ id: String) -> Bool {
        id.split(separator: "-").contains { component in
            guard component.count == 4, let year = Int(component) else { return false }
            return (2020...2099).contains(year)
        }
    }

    private static func gptGeneration(for id: String) -> GPTGeneration? {
        let value = id.lowercased()
        guard value.hasPrefix("gpt-") else { return nil }

        let versionTail = value.dropFirst(4)
        let version = versionTail.prefix { $0.isNumber || $0 == "." }
        let suffix = versionTail.dropFirst(version.count)
        guard suffix.isEmpty || suffix.first == "-" else { return nil }

        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count),
              let major = Int(parts[0]),
              parts.count == 1 || !parts[1].isEmpty,
              let minor = parts.count == 2 ? Int(parts[1]) : 0
        else {
            return nil
        }
        return GPTGeneration(major: major, minor: minor)
    }

    private static func modelVariantScore(_ id: String) -> Int {
        let value = id.lowercased()
        guard let generation = gptGeneration(for: value) else { return 3 }
        let base = generation.minor == 0
            ? "gpt-\(generation.major)"
            : "gpt-\(generation.major).\(generation.minor)"

        if value == base { return 0 }
        if value == "\(base)-pro" { return 1 }
        return 2
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

private struct GPTGeneration: Comparable, Hashable {
    let major: Int
    let minor: Int

    static func < (lhs: GPTGeneration, rhs: GPTGeneration) -> Bool {
        lhs.major == rhs.major
            ? lhs.minor < rhs.minor
            : lhs.major < rhs.major
    }
}
