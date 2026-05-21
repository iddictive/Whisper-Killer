import AppKit
import CryptoKit
import Foundation
import Network
import Security

struct GoogleDriveRecording: Identifiable, Equatable {
    let id: String
    let name: String
    let mimeType: String
    let modifiedTime: Date?
    let sizeBytes: Int64?
    let webViewLink: URL?

    var canImportForTranscription: Bool {
        mimeType.hasPrefix("audio/") || mimeType.hasPrefix("video/")
    }

    var displayDate: String {
        guard let modifiedTime else { return L.tr("Unknown date", "Дата неизвестна") }
        return Self.dateFormatter.string(from: modifiedTime)
    }

    var displaySize: String {
        guard let sizeBytes else { return "" }
        return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

struct GoogleCalendarMeeting: Identifiable, Equatable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date?
    let meetURL: URL?
    let meetingCode: String?
    var recording: GoogleDriveRecording?

    var timeRangeLabel: String {
        let start = Self.timeFormatter.string(from: startDate)
        guard let endDate else { return start }
        return "\(start)-\(Self.timeFormatter.string(from: endDate))"
    }

    var hasRecording: Bool {
        recording != nil
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}

enum GoogleDriveImportError: LocalizedError {
    case authCancelled
    case callbackFailed
    case invalidCallback
    case invalidTokenResponse
    case tokenMissing
    case apiError(String)
    case unsupportedFileType(String)

    var errorDescription: String? {
        switch self {
        case .authCancelled:
            return L.tr("Google connection was cancelled.", "Подключение Google отменено.")
        case .callbackFailed:
            return L.tr("Could not receive Google sign-in callback.", "Не удалось получить callback от Google.")
        case .invalidCallback:
            return L.tr("Google sign-in callback was invalid.", "Некорректный callback от Google.")
        case .invalidTokenResponse:
            return L.tr("Google returned an invalid token response.", "Google вернул некорректный ответ с токеном.")
        case .tokenMissing:
            return L.tr("Connect Google first.", "Сначала подключите Google.")
        case .apiError(let message):
            return message
        case .unsupportedFileType(let mimeType):
            return L.tr(
                "This Drive file cannot be imported as audio/video: \(mimeType)",
                "Этот файл Drive нельзя импортировать как аудио/видео: \(mimeType)"
            )
        }
    }
}

final class GoogleDriveMeetImporter {
    static let shared = GoogleDriveMeetImporter()

    private let clientID = "866553546280-ubksm2acb20871vndcrtde0nhdtblg3k.apps.googleusercontent.com"
    private let scopes = [
        "https://www.googleapis.com/auth/calendar.readonly",
        "https://www.googleapis.com/auth/meetings.space.readonly",
        "https://www.googleapis.com/auth/drive.meet.readonly",
        "https://www.googleapis.com/auth/drive.readonly"
    ]
    private let tokenStore = GoogleOAuthTokenStore()
    private let clientSecretStore = GoogleOAuthClientSecretStore()
    private let isoFormatter = ISO8601DateFormatter()

    private init() {}

    var isConnected: Bool {
        tokenStore.load()?.refreshToken?.isEmpty == false || tokenStore.load()?.accessToken.isEmpty == false
    }

    func disconnect() {
        tokenStore.delete()
    }

    func connect() async throws {
        let verifier = Self.randomURLSafeString(byteCount: 48)
        let challenge = Self.codeChallenge(for: verifier)
        let state = Self.randomURLSafeString(byteCount: 24)
        let callbackServer = GoogleOAuthLoopbackServer()
        let redirectURI = try await callbackServer.start()

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]

        guard let authURL = components.url else { throw GoogleDriveImportError.invalidCallback }
        await MainActor.run {
            _ = NSWorkspace.shared.open(authURL)
        }

        let params = try await callbackServer.waitForCallback()
        guard params["state"] == state else { throw GoogleDriveImportError.invalidCallback }
        if params["error"] != nil { throw GoogleDriveImportError.authCancelled }
        guard let code = params["code"], !code.isEmpty else { throw GoogleDriveImportError.invalidCallback }

        let token = try await exchangeAuthorizationCode(code, redirectURI: redirectURI, verifier: verifier)
        tokenStore.save(token)
    }

    func listRecentMeetRecordings(limit: Int = 25) async throws -> [GoogleDriveRecording] {
        let accessToken = try await validAccessToken()
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        components.queryItems = [
            URLQueryItem(
                name: "q",
                value: "trashed = false and (name contains 'Meet' or name contains 'Recording' or name contains 'recording')"
            ),
            URLQueryItem(name: "pageSize", value: "\(limit)"),
            URLQueryItem(name: "orderBy", value: "modifiedTime desc"),
            URLQueryItem(name: "supportsAllDrives", value: "true"),
            URLQueryItem(name: "includeItemsFromAllDrives", value: "true"),
            URLQueryItem(name: "fields", value: "files(id,name,mimeType,modifiedTime,size,webViewLink)")
        ]

        guard let url = components.url else { return [] }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validateHTTPResponse(response, data: data)

        let decoded = try JSONDecoder().decode(DriveFilesResponse.self, from: data)
        return decoded.files.map { file in
            GoogleDriveRecording(
                id: file.id,
                name: file.name,
                mimeType: file.mimeType,
                modifiedTime: file.modifiedTime.flatMap { isoFormatter.date(from: $0) },
                sizeBytes: file.size.flatMap(Int64.init),
                webViewLink: file.webViewLink.flatMap(URL.init(string:))
            )
        }
    }

    func listCalendarMeetings(on date: Date) async throws -> [GoogleCalendarMeeting] {
        let accessToken = try await validAccessToken()
        let bounds = dayBounds(for: date)
        let response = try await calendarEvents(start: bounds.start, end: bounds.end, accessToken: accessToken)

        var meetings = response.items.compactMap { event -> GoogleCalendarMeeting? in
            guard let startDate = event.start.resolvedDate(isoFormatter: isoFormatter) else { return nil }
            let endDate = event.end?.resolvedDate(isoFormatter: isoFormatter)
            let meetURL = event.resolvedMeetURL
            let meetingCode = event.resolvedMeetingCode

            guard meetURL != nil || meetingCode != nil else { return nil }

            return GoogleCalendarMeeting(
                id: event.id,
                title: event.summary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? L.tr("Untitled meeting", "Встреча без названия"),
                startDate: startDate,
                endDate: endDate,
                meetURL: meetURL,
                meetingCode: meetingCode,
                recording: nil
            )
        }

        for index in meetings.indices {
            guard let meetingCode = meetings[index].meetingCode else { continue }
            meetings[index].recording = try? await recordingForMeetingCode(
                meetingCode,
                start: bounds.start,
                end: bounds.end,
                accessToken: accessToken
            )
        }

        return meetings.sorted { $0.startDate < $1.startDate }
    }

    func downloadRecording(_ recording: GoogleDriveRecording) async throws -> URL {
        guard recording.canImportForTranscription else {
            throw GoogleDriveImportError.unsupportedFileType(recording.mimeType)
        }

        let accessToken = try await validAccessToken()
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files/\(recording.id)")!
        components.queryItems = [URLQueryItem(name: "alt", value: "media")]
        guard let url = components.url else { throw GoogleDriveImportError.invalidCallback }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
        try Self.validateHTTPResponse(response, data: nil)

        let destination = try destinationURL(for: recording)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    private func calendarEvents(start: Date, end: Date, accessToken: String) async throws -> CalendarEventsResponse {
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: isoFormatter.string(from: start)),
            URLQueryItem(name: "timeMax", value: isoFormatter.string(from: end)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "40"),
            URLQueryItem(name: "fields", value: "items(id,summary,start,end,hangoutLink,conferenceData(conferenceId,entryPoints(entryPointType,uri)))")
        ]

        guard let url = components.url else { throw GoogleDriveImportError.invalidCallback }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validateHTTPResponse(response, data: data)
        return try JSONDecoder().decode(CalendarEventsResponse.self, from: data)
    }

    private func recordingForMeetingCode(_ meetingCode: String, start: Date, end: Date, accessToken: String) async throws -> GoogleDriveRecording? {
        var components = URLComponents(string: "https://meet.googleapis.com/v2/conferenceRecords")!
        let filter = """
        space.meeting_code = "\(meetingCode)" AND start_time>="\(isoFormatter.string(from: start))" AND start_time<="\(isoFormatter.string(from: end))"
        """
        components.queryItems = [
            URLQueryItem(name: "pageSize", value: "10"),
            URLQueryItem(name: "filter", value: filter)
        ]

        guard let url = components.url else { throw GoogleDriveImportError.invalidCallback }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validateHTTPResponse(response, data: data)
        let records = try JSONDecoder().decode(ConferenceRecordsResponse.self, from: data).conferenceRecords ?? []

        for record in records {
            if let recording = try await firstGeneratedRecording(parent: record.name, accessToken: accessToken) {
                return recording
            }
        }

        return nil
    }

    private func firstGeneratedRecording(parent: String, accessToken: String) async throws -> GoogleDriveRecording? {
        var components = URLComponents(string: "https://meet.googleapis.com/v2/\(parent)/recordings")!
        components.queryItems = [URLQueryItem(name: "pageSize", value: "10")]
        guard let url = components.url else { throw GoogleDriveImportError.invalidCallback }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validateHTTPResponse(response, data: data)
        let recordings = try JSONDecoder().decode(MeetRecordingsResponse.self, from: data).recordings ?? []

        guard let generated = recordings.first(where: { $0.state == "FILE_GENERATED" }),
              let fileID = generated.driveDestination?.file,
              !fileID.isEmpty
        else { return nil }

        return try await driveFileMetadata(fileID: fileID, accessToken: accessToken)
            ?? GoogleDriveRecording(
                id: fileID,
                name: L.tr("Google Meet Recording.mp4", "Запись Google Meet.mp4"),
                mimeType: "video/mp4",
                modifiedTime: generated.endTime.flatMap { isoFormatter.date(from: $0) },
                sizeBytes: nil,
                webViewLink: generated.driveDestination?.exportUri.flatMap(URL.init(string:))
            )
    }

    private func driveFileMetadata(fileID: String, accessToken: String) async throws -> GoogleDriveRecording? {
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files/\(fileID)")!
        components.queryItems = [
            URLQueryItem(name: "supportsAllDrives", value: "true"),
            URLQueryItem(name: "fields", value: "id,name,mimeType,modifiedTime,size,webViewLink")
        ]

        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validateHTTPResponse(response, data: data)
        let file = try JSONDecoder().decode(DriveFile.self, from: data)

        return GoogleDriveRecording(
            id: file.id,
            name: file.name,
            mimeType: file.mimeType,
            modifiedTime: file.modifiedTime.flatMap { isoFormatter.date(from: $0) },
            sizeBytes: file.size.flatMap(Int64.init),
            webViewLink: file.webViewLink.flatMap(URL.init(string:))
        )
    }

    private func dayBounds(for date: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? date
        return (start, end)
    }

    private func validAccessToken() async throws -> String {
        guard var token = tokenStore.load() else { throw GoogleDriveImportError.tokenMissing }
        if token.expiresAt.timeIntervalSinceNow > 60 {
            return token.accessToken
        }

        guard let refreshToken = token.refreshToken, !refreshToken.isEmpty else {
            throw GoogleDriveImportError.tokenMissing
        }

        token = try await refreshAccessToken(refreshToken)
        tokenStore.save(token)
        return token.accessToken
    }

    private func exchangeAuthorizationCode(_ code: String, redirectURI: String, verifier: String) async throws -> GoogleOAuthToken {
        try await tokenRequest([
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ], existingRefreshToken: nil)
    }

    private func refreshAccessToken(_ refreshToken: String) async throws -> GoogleOAuthToken {
        try await tokenRequest([
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ], existingRefreshToken: refreshToken)
    }

    private func tokenRequest(_ parameters: [String: String], existingRefreshToken: String?) async throws -> GoogleOAuthToken {
        var requestParameters = parameters
        if let clientSecret = clientSecretStore.load(), !clientSecret.isEmpty {
            requestParameters["client_secret"] = clientSecret
        }

        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formURLEncoded(requestParameters).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validateHTTPResponse(response, data: data)

        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard !decoded.accessToken.isEmpty else { throw GoogleDriveImportError.invalidTokenResponse }
        return GoogleOAuthToken(
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken ?? existingRefreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(decoded.expiresIn ?? 3600))
        )
    }

    private func destinationURL(for recording: GoogleDriveRecording) throws -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let directory = appSupport.appendingPathComponent("WhisperKiller/GoogleMeetImports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let sanitizedName = Self.sanitizedFilename(recording.name)
        let ext = URL(fileURLWithPath: sanitizedName).pathExtension
        let filename: String
        if ext.isEmpty {
            filename = sanitizedName + Self.defaultExtension(for: recording.mimeType)
        } else {
            filename = sanitizedName
        }

        return directory.appendingPathComponent(filename)
    }

    private static func defaultExtension(for mimeType: String) -> String {
        if mimeType == "audio/mpeg" { return ".mp3" }
        if mimeType == "audio/mp4" || mimeType == "audio/x-m4a" { return ".m4a" }
        if mimeType == "video/quicktime" { return ".mov" }
        return ".mp4"
    }

    private static func sanitizedFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let components = name.components(separatedBy: invalid)
        let joined = components.joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? "Google Meet Recording" : joined
    }

    private static func validateHTTPResponse(_ response: URLResponse, data: Data?) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw GoogleDriveImportError.apiError(googleErrorMessage(statusCode: http.statusCode, data: data))
        }
    }

    private static func googleErrorMessage(statusCode: Int, data: Data?) -> String {
        let fallback = HTTPURLResponse.localizedString(forStatusCode: statusCode)
        guard let data else {
            return L.tr(
                "Google request failed: \(fallback).",
                "Запрос Google не выполнен: \(fallback)."
            )
        }

        if let decoded = try? JSONDecoder().decode(GoogleHTTPErrorResponse.self, from: data),
           let message = decoded.displayMessage {
            return message
        }

        let rawMessage = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawMessage, !rawMessage.isEmpty else {
            return L.tr(
                "Google request failed: \(fallback).",
                "Запрос Google не выполнен: \(fallback)."
            )
        }
        return L.tr(
            "Google request failed: \(rawMessage)",
            "Запрос Google не выполнен: \(rawMessage)"
        )
    }

    private static func formURLEncoded(_ parameters: [String: String]) -> String {
        parameters
            .map { key, value in
                "\(formURLEncode(key))=\(formURLEncode(value))"
            }
            .sorted()
            .joined(separator: "&")
    }

    private static func formURLEncode(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }
}

private struct GoogleOAuthToken: Codable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
}

private final class GoogleOAuthTokenStore {
    private let service = "WhisperKiller.GoogleDriveMeet"
    private let account = "OAuthToken"

    func load() -> GoogleOAuthToken? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(GoogleOAuthToken.self, from: data)
    }

    func save(_ token: GoogleOAuthToken) {
        guard let data = try? JSONEncoder().encode(token) else { return }
        delete()

        var query = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    func delete() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

private final class GoogleOAuthClientSecretStore {
    private let service = "WhisperKiller.GoogleOAuthClient"
    private let account = "DesktopClientSecret"

    func load() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let secret = String(data: data, encoding: .utf8)
        else { return nil }

        return secret.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

private final class GoogleOAuthLoopbackServer {
    private var listener: NWListener?
    private var callbackContinuation: CheckedContinuation<[String: String], Error>?
    private var readyContinuation: CheckedContinuation<String, Error>?

    func start() async throws -> String {
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }

        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                guard let port = listener.port else {
                    self?.readyContinuation?.resume(throwing: GoogleDriveImportError.callbackFailed)
                    self?.readyContinuation = nil
                    return
                }
                self?.readyContinuation?.resume(returning: "http://127.0.0.1:\(port.rawValue)/oauth2callback")
                self?.readyContinuation = nil
            case .failed(let error):
                self?.readyContinuation?.resume(throwing: error)
                self?.readyContinuation = nil
                self?.callbackContinuation?.resume(throwing: error)
                self?.callbackContinuation = nil
            default:
                break
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            readyContinuation = continuation
            listener.start(queue: .main)
        }
    }

    func waitForCallback() async throws -> [String: String] {
        try await withCheckedThrowingContinuation { continuation in
            callbackContinuation = continuation
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, error in
            guard let self else { return }
            if let error {
                self.callbackContinuation?.resume(throwing: error)
                self.callbackContinuation = nil
                self.stop()
                return
            }

            guard let data,
                  let request = String(data: data, encoding: .utf8),
                  let firstLine = request.components(separatedBy: "\r\n").first,
                  let path = firstLine.split(separator: " ").dropFirst().first,
                  let url = URL(string: "http://127.0.0.1\(path)")
            else {
                self.callbackContinuation?.resume(throwing: GoogleDriveImportError.invalidCallback)
                self.callbackContinuation = nil
                self.stop()
                return
            }

            let params = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .reduce(into: [String: String]()) { result, item in
                    result[item.name] = item.value
                } ?? [:]

            self.sendResponse(on: connection)
            self.callbackContinuation?.resume(returning: params)
            self.callbackContinuation = nil
            self.stop()
        }
    }

    private func sendResponse(on connection: NWConnection) {
        let body = """
        <html><body style="font: -apple-system-body; padding: 32px;">
        <h2>Google response received</h2>
        <p>Return to WhisperKiller to finish connecting.</p>
        </body></html>
        """
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(Data(body.utf8).count)\r
        Connection: close\r
        \r
        \(body)
        """
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func stop() {
        listener?.cancel()
        listener = nil
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

private struct GoogleHTTPErrorResponse: Decodable {
    let error: GoogleHTTPErrorValue?
    let errorDescription: String?

    var displayMessage: String? {
        let description = errorDescription?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let errorText = error?.message?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        switch (errorText, description) {
        case let (.some(errorText), .some(description)) where errorText != description:
            return L.tr(
                "Google request failed: \(errorText). \(description)",
                "Запрос Google не выполнен: \(errorText). \(description)"
            )
        case let (.some(errorText), _):
            return L.tr(
                "Google request failed: \(errorText)",
                "Запрос Google не выполнен: \(errorText)"
            )
        case let (_, .some(description)):
            return L.tr(
                "Google request failed: \(description)",
                "Запрос Google не выполнен: \(description)"
            )
        default:
            return nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

private enum GoogleHTTPErrorValue: Decodable {
    case text(String)
    case object(GoogleHTTPErrorObject)

    var message: String? {
        switch self {
        case .text(let value):
            return value
        case .object(let object):
            return object.message ?? object.status
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .text(value)
            return
        }
        self = .object(try container.decode(GoogleHTTPErrorObject.self))
    }
}

private struct GoogleHTTPErrorObject: Decodable {
    let message: String?
    let status: String?
}

private struct DriveFilesResponse: Decodable {
    let files: [DriveFile]
}

private struct CalendarEventsResponse: Decodable {
    let items: [CalendarEvent]
}

private struct CalendarEvent: Decodable {
    let id: String
    let summary: String?
    let start: CalendarEventDate
    let end: CalendarEventDate?
    let hangoutLink: String?
    let conferenceData: CalendarConferenceData?

    var resolvedMeetURL: URL? {
        if let hangoutLink, let url = URL(string: hangoutLink) {
            return url
        }

        return conferenceData?.entryPoints?
            .first(where: { $0.entryPointType == "video" })?
            .uri
            .flatMap(URL.init(string:))
    }

    var resolvedMeetingCode: String? {
        if let conferenceID = conferenceData?.conferenceId?.normalizedMeetCode {
            return conferenceID
        }

        guard let url = resolvedMeetURL else { return nil }
        return url.lastPathComponent.normalizedMeetCode
    }
}

private struct CalendarEventDate: Decodable {
    let date: String?
    let dateTime: String?

    func resolvedDate(isoFormatter: ISO8601DateFormatter) -> Date? {
        if let dateTime {
            return isoFormatter.date(from: dateTime)
        }

        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.date(from: date)
    }
}

private struct CalendarConferenceData: Decodable {
    let conferenceId: String?
    let entryPoints: [CalendarEntryPoint]?
}

private struct CalendarEntryPoint: Decodable {
    let entryPointType: String?
    let uri: String?
}

private struct ConferenceRecordsResponse: Decodable {
    let conferenceRecords: [ConferenceRecord]?
}

private struct ConferenceRecord: Decodable {
    let name: String
}

private struct MeetRecordingsResponse: Decodable {
    let recordings: [MeetRecording]?
}

private struct MeetRecording: Decodable {
    let state: String?
    let endTime: String?
    let driveDestination: MeetDriveDestination?
}

private struct MeetDriveDestination: Decodable {
    let file: String?
    let exportUri: String?
}

private struct DriveFile: Decodable {
    let id: String
    let name: String
    let mimeType: String
    let modifiedTime: String?
    let size: String?
    let webViewLink: String?
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var normalizedMeetCode: String? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let cleaned = unicodeScalars
            .filter { allowed.contains($0) }
            .map(String.init)
            .joined()
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        return cleaned.isEmpty ? nil : cleaned
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
