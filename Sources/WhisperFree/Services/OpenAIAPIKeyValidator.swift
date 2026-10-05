import Foundation
import Darwin

enum OpenAIAPIKeyValidationState: Equatable {
    case idle
    case checking
    case valid
    case invalid
    case networkError(String)
    case failed(statusCode: Int)
}

struct OpenAINetworkDiagnosticReport {
    let lines: [String]
    let isSuccessful: Bool
}

enum OpenAIAPIKeyValidator {
    static func validate(_ apiKey: String, configuration: CloudAPIConfiguration = .init()) async -> OpenAIAPIKeyValidationState {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return .idle }

        let url: URL
        do {
            url = try configuration.apiURL(path: "models")
        } catch {
            return .networkError(error.localizedDescription)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failed(statusCode: -1)
            }

            switch httpResponse.statusCode {
            case 200:
                return .valid
            case 401:
                return .invalid
            default:
                return .failed(statusCode: httpResponse.statusCode)
            }
        } catch {
            if let urlError = error as? URLError {
                return .networkError(Self.message(for: urlError, host: url.host ?? "provider"))
            }
            return .networkError(error.localizedDescription)
        }
    }

    private static func message(for error: URLError, host: String) -> String {
        switch error.code {
        case .notConnectedToInternet:
            return "No internet connection."
        case .timedOut:
            return "The connection to \(host) timed out."
        case .cannotFindHost, .dnsLookupFailed:
            return "DNS could not resolve \(host)."
        case .cannotConnectToHost, .networkConnectionLost:
            return "The connection to \(host) was interrupted."
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot:
            return "TLS connection to \(host) failed."
        default:
            return error.localizedDescription
        }
    }

    static func diagnoseNetwork(configuration: CloudAPIConfiguration = .init()) async -> OpenAINetworkDiagnosticReport {
        let endpoint: URL
        do {
            endpoint = try configuration.apiURL(path: "models")
        } catch {
            return OpenAINetworkDiagnosticReport(lines: [error.localizedDescription], isSuccessful: false)
        }
        let host = endpoint.host ?? "provider"
        var lines: [String] = []
        var successCount = 0

        let internetOK = await checkInternetReachability()
        lines.append(internetOK ? "1. Internet: OK" : "1. Internet: Failed")
        if internetOK { successCount += 1 }

        let dnsOK = resolveHost(host)
        lines.append(dnsOK ? "2. DNS for \(host): OK" : "2. DNS for \(host): Failed")
        if dnsOK { successCount += 1 }

        let providerReachable = await checkProviderReachability(endpoint)
        lines.append(providerReachable ? "3. \(host) API endpoint: OK" : "3. \(host) API endpoint: Failed")
        if providerReachable { successCount += 1 }

        return OpenAINetworkDiagnosticReport(lines: lines, isSuccessful: successCount == 3)
    }

    private static func checkInternetReachability() async -> Bool {
        guard let url = URL(string: "https://www.apple.com/library/test/success.html") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return (200..<400).contains(httpResponse.statusCode)
        } catch {
            return false
        }
    }

    private static func checkProviderReachability(_ url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return httpResponse.statusCode == 401 || (200..<500).contains(httpResponse.statusCode)
        } catch {
            return false
        }
    }

    private static func resolveHost(_ host: String) -> Bool {
        var hints = addrinfo(
            ai_flags: AI_DEFAULT,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: 0,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )

        var infoPointer: UnsafeMutablePointer<addrinfo>?
        let result = getaddrinfo(host, nil, &hints, &infoPointer)
        if let infoPointer {
            freeaddrinfo(infoPointer)
        }
        return result == 0
    }
}
