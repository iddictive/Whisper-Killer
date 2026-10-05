import Foundation

struct HistoryStorageSummary: Equatable {
    var recordingsBytes: Int64 = 0
    var recordingCount = 0
    var downloadsBytes: Int64 = 0
    var downloadCount = 0
    var modelsBytes: Int64 = 0
    var otherBytes: Int64 = 0
    var textBytes: Int64 = 0

    var totalBytes: Int64 { recordingsBytes + downloadsBytes + modelsBytes + otherBytes + textBytes }
    var mediaBytes: Int64 { recordingsBytes + downloadsBytes }

    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

enum HistoryStorageCleanup: String, Identifiable {
    case recordings, downloads, history
    var id: String { rawValue }
}

struct RecordingCleanupResult {
    var removedPaths = Set<String>()
    var failureCount = 0
}

/// Disk I/O stays off the UI actor. Only the application's own regular files are removable.
actor HistoryStorage {
    static let shared = HistoryStorage()
    private let directory: URL
    private let fileManager: FileManager

    init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directory = directory ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WhisperKiller", isDirectory: true)
    }

    func summary(textBytes: Int64) throws -> HistoryStorageSummary {
        var result = HistoryStorageSummary(textBytes: textBytes)
        for url in try regularFiles(in: directory) {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            let bytes = Int64(values.fileSize ?? 0)
            let relative = url.standardizedFileURL.path.dropFirst(directory.standardizedFileURL.path.count + 1)
            switch relative.split(separator: "/").first {
            case "Recordings":
                result.recordingsBytes += bytes
                result.recordingCount += 1
            case "GoogleMeetImports":
                result.downloadsBytes += bytes
                if url.lastPathComponent != "downloads.json" { result.downloadCount += 1 }
            case "Models", "Parakeet", "QwenASR": result.modelsBytes += bytes
            default: result.otherBytes += bytes
            }
        }
        return result
    }

    func removeRecordings() throws -> RecordingCleanupResult {
        var result = RecordingCleanupResult()
        for url in try regularFiles(in: directory.appendingPathComponent("Recordings", isDirectory: true)) {
            do {
                try fileManager.removeItem(at: url)
                result.removedPaths.insert(url.standardizedFileURL.path)
            } catch {
                result.failureCount += 1
            }
        }
        return result
    }

    private func regularFiles(in folder: URL) throws -> [URL] {
        guard fileManager.fileExists(atPath: folder.path) else { return [] }
        // Refuse a redirected root, and never follow links inside it.
        guard folder.standardizedFileURL == folder.resolvingSymlinksInPath().standardizedFileURL else {
            throw CocoaError(.fileReadNoPermission)
        }
        var enumerationError: Error?
        guard let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            errorHandler: { _, error in enumerationError = error; return false }
        ) else { throw CocoaError(.fileReadUnknown) }
        var files: [URL] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink != true && values.isRegularFile == true {
                files.append(url.standardizedFileURL)
            }
        }
        if let enumerationError { throw enumerationError }
        return files
    }
}
