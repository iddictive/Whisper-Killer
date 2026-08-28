import Foundation

struct OpenAIModelCatalog {
    let modelIDs: [String]

    static let bootstrapTranscriptionModels: [CloudTranscriptionModel] = [
        .gptTranscribe,
        .whisper1,
        .gpt4oMiniTranscribe,
        .gpt4oTranscribe
    ]

    static func fetch(apiKey: String) async throws -> OpenAIModelCatalog {
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
            let errorText = errorMessage(from: data) ?? "HTTP \(httpResponse.statusCode)"
            throw TranscriptionError.networkError("OpenAI model list failed: \(errorText)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]]
        else {
            throw TranscriptionError.invalidResponse
        }

        return OpenAIModelCatalog(
            modelIDs: dataArray.compactMap { $0["id"] as? String }
        )
    }

    var transcriptionModels: [CloudTranscriptionModel] {
        Self.relevantTranscriptionModels(from: modelIDs)
    }

    var baseTranscriptionModels: [CloudTranscriptionModel] {
        transcriptionModels.filter { !$0.usesNativeDiarization }
    }

    var diarizationModels: [CloudTranscriptionModel] {
        transcriptionModels.filter(\.usesNativeDiarization)
    }

    static func relevantTranscriptionModels(from ids: [String]) -> [CloudTranscriptionModel] {
        Set(
            ids.compactMap { id -> CloudTranscriptionModel? in
                let value = id.lowercased()
                guard !hasSnapshotDate(value) else { return nil }
                guard !value.contains("-live-transcribe"), !value.contains("-realtime-") else {
                    return nil
                }
                guard value == CloudTranscriptionModel.whisper1.apiName
                        || (value.hasPrefix("gpt-") && value.contains("-transcribe"))
                else {
                    return nil
                }
                return CloudTranscriptionModel(rawValue: id)
            }
        )
        .sorted { lhs, rhs in
            if lhs == .whisper1 { return false }
            if rhs == .whisper1 { return true }
            return lhs.apiName.localizedStandardCompare(rhs.apiName) == .orderedDescending
        }
    }

    private static func hasSnapshotDate(_ id: String) -> Bool {
        id.split(separator: "-").contains { component in
            guard component.count == 4, let year = Int(component) else { return false }
            return (2020...2099).contains(year)
        }
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String
        else {
            return nil
        }
        return message
    }
}
