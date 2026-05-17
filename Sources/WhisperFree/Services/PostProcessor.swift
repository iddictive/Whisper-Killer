import Foundation

struct ProcessedResult {
    let text: String
    let promptTokens: Int
    let completionTokens: Int
    let engine: PostProcessingEngine
}

final class PostProcessor {
    private let settings: AppSettings
    private let localEngine = LocalTranslationEngine()

    init(settings: AppSettings) {
        self.settings = settings
    }

    func process(text: String, mode: TranscriptionMode) async throws -> ProcessedResult {
        let engine = PostProcessingEngine.openai
        let apiKey = settings.normalizedAPIKey
        
        guard !apiKey.isEmpty else { throw TranscriptionError.noAPIKey }
        guard !text.isEmpty else { return ProcessedResult(text: text, promptTokens: 0, completionTokens: 0, engine: engine) }

        let chunks = splitTextForProcessing(text)
        guard chunks.count > 1 else {
            return try await openAIChat(systemPrompt: mode.systemPrompt, userText: text, temperature: 0.3, maxTokens: nil)
        }

        var processedChunks: [String] = []
        var promptTokens = 0
        var completionTokens = 0

        for (index, chunk) in chunks.enumerated() {
            let result = try await openAIChat(
                systemPrompt: mode.systemPrompt,
                userText: "Chunk \(index + 1) of \(chunks.count):\n\n\(chunk)",
                temperature: 0.3,
                maxTokens: nil
            )
            processedChunks.append(result.text)
            promptTokens += result.promptTokens
            completionTokens += result.completionTokens
        }

        return ProcessedResult(
            text: processedChunks.joined(separator: "\n\n"),
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            engine: engine
        )
    }

    func diarize(text: String) async throws -> ProcessedResult {
        let apiKey = settings.normalizedAPIKey
        guard !apiKey.isEmpty else { throw TranscriptionError.noAPIKey }
        guard !text.isEmpty else { return ProcessedResult(text: text, promptTokens: 0, completionTokens: 0, engine: .openai) }

        let systemPrompt = """
        Analyze the following transcription and format it by spliting speech between different speakers based on context, tone, and turn-taking. 
        Use the format:
        Speaker A: [speech]
        Speaker B: [speech]
        ...
        Output ONLY the diarized text. Do not add any introduction or conclusion. Keep the original words exactly as transcribed.
        """

        let chunks = splitTextForProcessing(text)
        guard chunks.count > 1 else {
            return try await openAIChat(systemPrompt: systemPrompt, userText: text, temperature: 0.2, maxTokens: 4096)
        }

        var diarizedChunks: [String] = []
        var promptTokens = 0
        var completionTokens = 0

        for (index, chunk) in chunks.enumerated() {
            let result = try await openAIChat(
                systemPrompt: systemPrompt,
                userText: "Chunk \(index + 1) of \(chunks.count):\n\n\(chunk)",
                temperature: 0.2,
                maxTokens: 4096
            )
            diarizedChunks.append(result.text)
            promptTokens += result.promptTokens
            completionTokens += result.completionTokens
        }

        return ProcessedResult(
            text: diarizedChunks.joined(separator: "\n\n"),
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            engine: .openai
        )
    }

    func summarizeTranscript(text: String) async throws -> ProcessedResult {
        let trimmedText = TranscriptSanitizer.cleanForSummarization(text)
        guard !trimmedText.isEmpty else {
            return ProcessedResult(text: text, promptTokens: 0, completionTokens: 0, engine: .openai)
        }

        let systemPrompt = """
        You create concise follow-up notes from a transcription.
        Return clean markdown with exactly these sections:
        ## Topics
        ## Speaker Threads
        ## Decisions
        ## Action Items
        ## Open Questions

        Rules:
        - Use only information present in the transcript.
        - Keep it concise and practical.
        - Under Speaker Threads, summarize who talked about what. If speakers are not identifiable, say that explicitly.
        - Under Action Items, include owners only when the transcript clearly implies them.
        - If a section has no information, write "- None identified."
        - Do not add any intro or outro outside those sections.
        """

        let engine = try await resolveFollowUpEngine()
        let chunks = splitTextForFollowUp(trimmedText)

        guard chunks.count > 1 else {
            return try await runFollowUpChat(
                engine: engine,
                systemPrompt: systemPrompt,
                userText: trimmedText,
                temperature: 0.2,
                maxTokens: 2048
            )
        }

        let chunkPrompt = """
        Extract compact follow-up notes from this transcript chunk.
        Preserve concrete facts, decisions, owners, dates, blockers, and open questions.
        Ignore obvious ASR artifacts such as repeated identical phrases, standalone ellipses, and subtitle credits.
        Use only information present in the chunk.
        Return concise markdown bullets under:
        ## Topics
        ## Speaker Threads
        ## Decisions
        ## Action Items
        ## Open Questions
        """

        var partials: [String] = []
        var promptTokens = 0
        var completionTokens = 0

        for (index, chunk) in chunks.enumerated() {
            let result = try await runFollowUpChat(
                engine: engine,
                systemPrompt: chunkPrompt,
                userText: "Chunk \(index + 1) of \(chunks.count):\n\n\(chunk)",
                temperature: 0.1,
                maxTokens: 1200
            )
            partials.append(result.text)
            promptTokens += result.promptTokens
            completionTokens += result.completionTokens
        }

        let combinedNotes = partials.enumerated()
            .map { "Chunk \($0.offset + 1):\n\($0.element)" }
            .joined(separator: "\n\n")
        let finalResult = try await runFollowUpChat(
            engine: engine,
            systemPrompt: systemPrompt,
            userText: combinedNotes,
            temperature: 0.1,
            maxTokens: 2048
        )

        return ProcessedResult(
            text: finalResult.text,
            promptTokens: promptTokens + finalResult.promptTokens,
            completionTokens: completionTokens + finalResult.completionTokens,
            engine: finalResult.engine
        )
    }

    private func runFollowUpChat(
        engine: FollowUpEngine,
        systemPrompt: String,
        userText: String,
        temperature: Double,
        maxTokens: Int?
    ) async throws -> ProcessedResult {
        switch engine {
        case .openAI:
            return try await openAIChat(
                systemPrompt: systemPrompt,
                userText: userText,
                temperature: temperature,
                maxTokens: maxTokens
            )
        case .ollama(let model):
            let content = try await localEngine.chat(
                systemPrompt: systemPrompt,
                userText: userText,
                model: model,
                temperature: temperature
            )
            return ProcessedResult(
                text: content,
                promptTokens: 0,
                completionTokens: 0,
                engine: .ollama
            )
        }
    }

    private func splitTextForFollowUp(_ text: String, maxCharacters: Int = 12_000) -> [String] {
        guard text.count > maxCharacters else { return [text] }

        return splitText(text, maxCharacters: maxCharacters)
    }

    private func splitTextForProcessing(_ text: String, maxCharacters: Int = 6_000) -> [String] {
        guard text.count > maxCharacters else { return [text] }

        return splitText(text, maxCharacters: maxCharacters)
    }

    private func splitText(_ text: String, maxCharacters: Int) -> [String] {
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var chunks: [String] = []
        var current = ""

        for word in words {
            let nextLength = current.isEmpty ? word.count : current.count + word.count + 1
            if nextLength > maxCharacters, !current.isEmpty {
                chunks.append(current)
                current = word
            } else {
                current = current.isEmpty ? word : current + " " + word
            }
        }

        if !current.isEmpty {
            chunks.append(current)
        }

        return chunks
    }

    private func openAIChat(systemPrompt: String, userText: String, temperature: Double, maxTokens: Int?) async throws -> ProcessedResult {
        let engine = PostProcessingEngine.openai
        let apiKey = settings.normalizedAPIKey
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        let model = "gpt-4o-mini"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userText]
            ],
            "temperature": temperature
        ]
        if let maxTokens {
            payload["max_tokens"] = maxTokens
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, httpResponse) = try await TransientHTTPRetry.data(for: request, label: "OpenAI chat")

        if httpResponse.statusCode == 401 {
            throw TranscriptionError.networkError("Invalid API Key for \(engine.rawValue).")
        }

        if httpResponse.statusCode == 429 {
            let errorText = openAIErrorMessage(from: data) ?? "OpenAI quota exceeded. Check billing and project limits."
            throw TranscriptionError.networkError("HTTP 429: \(errorText)")
        }

        guard httpResponse.statusCode == 200 else {
            let errorText = openAIErrorMessage(from: data) ?? String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TranscriptionError.networkError("\(engine.rawValue) post-processing failed: \(errorText)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String,
              let usage = json["usage"] as? [String: Any]
        else {
            throw TranscriptionError.invalidResponse
        }

        return ProcessedResult(
            text: content.trimmingCharacters(in: .whitespacesAndNewlines),
            promptTokens: usage["prompt_tokens"] as? Int ?? 0,
            completionTokens: usage["completion_tokens"] as? Int ?? 0,
            engine: engine
        )
    }

    private func openAIErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return nil
        }
        return message
    }

    private enum FollowUpEngine {
        case openAI
        case ollama(model: String)
    }

    private func resolveFollowUpEngine() async throws -> FollowUpEngine {
        let localModel = settings.liveTranslatorLocalModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let preferLocal = settings.liveTranslatorEngine == .local

        if preferLocal, let localEngine = await availableLocalEngine(model: localModel) {
            return localEngine
        }

        if settings.hasOpenAIAPIKey {
            return .openAI
        }

        if let localEngine = await availableLocalEngine(model: localModel) {
            return localEngine
        }

        throw TranscriptionError.networkError(
            "No AI follow-up engine is available. Add an OpenAI API key or start Ollama with a downloaded local model."
        )
    }

    private func availableLocalEngine(model: String) async -> FollowUpEngine? {
        guard !model.isEmpty else { return nil }
        guard await localEngine.isRunning() else { return nil }
        guard await localEngine.checkModelExists(name: model) else { return nil }
        return .ollama(model: model)
    }
}
