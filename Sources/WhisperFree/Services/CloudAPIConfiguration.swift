import Foundation

enum CloudProvider: String, Codable, CaseIterable, Sendable {
    case openAI = "OpenAI"
    case custom = "OpenAI-compatible"
}

struct CloudAPIConfiguration: Equatable, Sendable {
    var provider: CloudProvider = .openAI
    var customBaseURL: String = ""

    var isOpenAI: Bool { provider == .openAI }

    func apiURL(path: String) throws -> URL {
        let value = isOpenAI ? "https://api.openai.com/v1" : customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let base = URL(string: value),
              let scheme = base.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = base.host, !host.isEmpty,
              base.user == nil, base.password == nil, base.query == nil, base.fragment == nil
        else {
            throw TranscriptionError.networkError("Enter a valid API base URL, including the provider's API path (for example, https://provider.example/v1).")
        }
        return base.appendingPathComponent(path)
    }
}
