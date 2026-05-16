import Foundation

enum MarkdownTranscriptExporter {
    static func save(text: String, nextToSourceFile sourceURL: URL) throws -> URL {
        let destinationURL = nextAvailableMarkdownURL(nextToSourceFile: sourceURL)
        try (text + "\n").write(to: destinationURL, atomically: true, encoding: .utf8)
        return destinationURL
    }

    private static func nextAvailableMarkdownURL(nextToSourceFile sourceURL: URL) -> URL {
        let directory = sourceURL.deletingLastPathComponent()
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let fileManager = FileManager.default
        var candidate = directory.appendingPathComponent(baseName).appendingPathExtension("md")
        var index = 2

        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName) \(index)").appendingPathExtension("md")
            index += 1
        }

        return candidate
    }
}
