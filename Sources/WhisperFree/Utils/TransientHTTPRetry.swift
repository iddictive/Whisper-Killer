import Foundation

enum TransientHTTPRetry {
    static func data(for request: URLRequest, label: String, maxRetries: Int = 2) async throws -> (Data, HTTPURLResponse) {
        var attempt = 0

        while true {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw TranscriptionError.invalidResponse
                }

                if isTransientStatus(httpResponse.statusCode), attempt < maxRetries {
                    print("whisper_debug: \(label) transient HTTP \(httpResponse.statusCode), retry \(attempt + 1)/\(maxRetries)")
                    try await Task.sleep(nanoseconds: retryDelayNanoseconds(for: attempt))
                    attempt += 1
                    continue
                }

                return (data, httpResponse)
            } catch {
                guard !Task.isCancelled else { throw error }

                if isRetryableTransportError(error), attempt < maxRetries {
                    print("whisper_debug: \(label) transient network error, retry \(attempt + 1)/\(maxRetries): \(error.localizedDescription)")
                    try await Task.sleep(nanoseconds: retryDelayNanoseconds(for: attempt))
                    attempt += 1
                    continue
                }

                throw error
            }
        }
    }

    static func isTransientStatus(_ statusCode: Int) -> Bool {
        [500, 502, 503, 504].contains(statusCode)
    }

    private static func isRetryableTransportError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }

        switch URLError.Code(rawValue: nsError.code) {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }

    private static func retryDelayNanoseconds(for attempt: Int) -> UInt64 {
        let delays: [UInt64] = [
            500_000_000,
            1_000_000_000,
            2_000_000_000
        ]
        return delays[min(attempt, delays.count - 1)]
    }
}
