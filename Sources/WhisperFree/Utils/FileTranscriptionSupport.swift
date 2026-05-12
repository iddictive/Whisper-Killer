import Foundation
import UniformTypeIdentifiers

enum FileTranscriptionSupport {
    static let allowedContentTypes: [UTType] = [
        .audio,
        .video,
        .movie,
        .quickTimeMovie,
        .mpeg4Movie,
        .wav,
        .mp3,
        .aiff
    ]

    private static let supportedExtensions: Set<String> = [
        "aif",
        "aiff",
        "avi",
        "flac",
        "m4a",
        "m4v",
        "mkv",
        "mov",
        "mp3",
        "mp4",
        "ogg",
        "wav",
        "webm"
    ]

    static func isSupported(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }

        let ext = url.pathExtension.lowercased()
        if supportedExtensions.contains(ext) {
            return true
        }

        if let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return contentType.conforms(to: .audio)
                || contentType.conforms(to: .video)
                || contentType.conforms(to: .movie)
        }

        return false
    }

    static func supportedURLs(from urls: [URL]) -> [URL] {
        urls.filter(isSupported)
    }
}

struct FileTranscriptionImportRequest: Identifiable, Equatable {
    let id = UUID()
    let urls: [URL]
}
