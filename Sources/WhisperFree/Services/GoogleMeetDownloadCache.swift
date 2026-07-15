import CryptoKit
import Foundation

struct GoogleMeetDownloadSummary: Equatable {
    let fileCount: Int
    let totalBytes: Int64

    static let empty = GoogleMeetDownloadSummary(fileCount: 0, totalBytes: 0)

    var displaySize: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
}

actor GoogleMeetDownloadCache {
    static let shared = GoogleMeetDownloadCache()

    private struct Manifest: Codable {
        var entries: [String: Entry] = [:]
    }

    private struct Entry: Codable {
        let recordingID: String
        var meetingIDs: [String]
        let filename: String
        let byteCount: Int64
        let cachedAt: Date
    }

    private let fileManager: FileManager
    private let directory: URL
    private let manifestURL: URL

    init(fileManager: FileManager = .default, directory: URL? = nil) {
        self.fileManager = fileManager
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.directory = directory
            ?? appSupport.appendingPathComponent("WhisperKiller/GoogleMeetImports", isDirectory: true)
        self.manifestURL = self.directory.appendingPathComponent("downloads.json")
    }

    func localURL(for recording: GoogleDriveRecording, meetingID: String? = nil) throws -> URL? {
        var manifest = loadManifest()

        if var entry = manifest.entries[recording.id] {
            let url = directory.appendingPathComponent(entry.filename)
            guard isValidFile(url, expectedBytes: entry.byteCount) else {
                manifest.entries[recording.id] = nil
                try saveManifest(manifest)
                return nil
            }
            if bind(meetingID, to: &entry) {
                manifest.entries[recording.id] = entry
                try saveManifest(manifest)
            }
            return url
        }

        let legacyURL = directory.appendingPathComponent(Self.legacyFilename(for: recording))
        guard isValidFile(legacyURL, expectedBytes: recording.sizeBytes) else { return nil }

        let byteCount = try fileSize(at: legacyURL)
        manifest.entries[recording.id] = Entry(
            recordingID: recording.id,
            meetingIDs: meetingID.map { [$0] } ?? [],
            filename: legacyURL.lastPathComponent,
            byteCount: byteCount,
            cachedAt: Date()
        )
        try saveManifest(manifest)
        return legacyURL
    }

    func store(
        temporaryURL: URL,
        recording: GoogleDriveRecording,
        meetingID: String? = nil
    ) throws -> URL {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        var manifest = loadManifest()
        if let existing = manifest.entries[recording.id] {
            let existingURL = directory.appendingPathComponent(existing.filename)
            if fileManager.fileExists(atPath: existingURL.path) {
                try fileManager.removeItem(at: existingURL)
            }
        }

        let filename = Self.managedFilename(for: recording)
        let destination = directory.appendingPathComponent(filename)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temporaryURL, to: destination)

        let byteCount = try fileSize(at: destination)
        manifest.entries[recording.id] = Entry(
            recordingID: recording.id,
            meetingIDs: meetingID.map { [$0] } ?? [],
            filename: filename,
            byteCount: byteCount,
            cachedAt: Date()
        )
        try saveManifest(manifest)
        return destination
    }

    @discardableResult
    func delete(recordingID: String) throws -> Bool {
        var manifest = loadManifest()
        guard let entry = manifest.entries.removeValue(forKey: recordingID) else { return false }
        let url = directory.appendingPathComponent(entry.filename)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try saveManifest(manifest)
        return true
    }

    func clear() throws -> GoogleMeetDownloadSummary {
        let summary = try summary()
        for url in try downloadedFiles() {
            try fileManager.removeItem(at: url)
        }
        try saveManifest(Manifest())
        return summary
    }

    func summary() throws -> GoogleMeetDownloadSummary {
        var manifest = loadManifest()
        var validEntries: [String: Entry] = [:]
        for (recordingID, entry) in manifest.entries {
            let url = directory.appendingPathComponent(entry.filename)
            guard isValidFile(url, expectedBytes: entry.byteCount) else { continue }
            validEntries[recordingID] = entry
        }

        if validEntries.count != manifest.entries.count {
            manifest.entries = validEntries
            try saveManifest(manifest)
        }
        let files = try downloadedFiles()
        let totalBytes = try files.reduce(Int64(0)) { total, url in
            total + (try fileSize(at: url))
        }
        return GoogleMeetDownloadSummary(fileCount: files.count, totalBytes: totalBytes)
    }

    private func loadManifest() -> Manifest {
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data)
        else { return Manifest() }
        return manifest
    }

    private func saveManifest(_ manifest: Manifest) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
    }

    private func bind(_ meetingID: String?, to entry: inout Entry) -> Bool {
        guard let meetingID, !entry.meetingIDs.contains(meetingID) else { return false }
        entry.meetingIDs.append(meetingID)
        entry.meetingIDs.sort()
        return true
    }

    private func isValidFile(_ url: URL, expectedBytes: Int64?) -> Bool {
        guard fileManager.fileExists(atPath: url.path),
              let actualBytes = try? fileSize(at: url),
              actualBytes > 0
        else { return false }
        guard let expectedBytes, expectedBytes > 0 else { return true }
        return actualBytes == expectedBytes
    }

    private func fileSize(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }

    private func downloadedFiles() throws -> [URL] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        return try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter { url in
            guard url.lastPathComponent != manifestURL.lastPathComponent else { return false }
            return (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }

    private static func managedFilename(for recording: GoogleDriveRecording) -> String {
        let legacy = legacyFilename(for: recording)
        let url = URL(fileURLWithPath: legacy)
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let digest = SHA256.hash(data: Data(recording.id.utf8))
        let suffix = digest.prefix(6).map { String(format: "%02x", $0) }.joined()
        return ext.isEmpty ? "\(stem)--\(suffix)" : "\(stem)--\(suffix).\(ext)"
    }

    private static func legacyFilename(for recording: GoogleDriveRecording) -> String {
        let sanitized = sanitizedFilename(recording.name)
        guard URL(fileURLWithPath: sanitized).pathExtension.isEmpty else { return sanitized }
        return sanitized + defaultExtension(for: recording.mimeType)
    }

    private static func sanitizedFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Google Meet Recording" : cleaned
    }

    private static func defaultExtension(for mimeType: String) -> String {
        if mimeType == "audio/mpeg" { return ".mp3" }
        if mimeType == "audio/mp4" || mimeType == "audio/x-m4a" { return ".m4a" }
        if mimeType == "video/quicktime" { return ".mov" }
        return ".mp4"
    }
}
