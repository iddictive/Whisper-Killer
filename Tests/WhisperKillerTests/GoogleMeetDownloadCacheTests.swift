import Foundation
import XCTest
@testable import WhisperKiller

final class GoogleMeetDownloadCacheTests: XCTestCase {
    func testStoredRecordingIsReusedForAnotherMeeting() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let cache = GoogleMeetDownloadCache(directory: directory)
        let recording = recording(id: "drive-file-1", name: "Weekly Sync.mp4", size: 4)
        let temporaryFile = directory.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try Data([1, 2, 3, 4]).write(to: temporaryFile)

        let storedURL = try await cache.store(
            temporaryURL: temporaryFile,
            recording: recording,
            meetingID: "meeting-a"
        )
        let reusedURL = try await cache.localURL(for: recording, meetingID: "meeting-b")

        XCTAssertEqual(reusedURL, storedURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storedURL.path))
        let summary = try await cache.summary()
        XCTAssertEqual(summary.fileCount, 1)
        XCTAssertEqual(summary.totalBytes, 4)
    }

    func testLegacyFileWithWrongSizeIsNotReused() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let cache = GoogleMeetDownloadCache(directory: directory)
        let recording = recording(id: "drive-file-2", name: "Design Review.mp4", size: 10)
        try Data([1, 2, 3]).write(to: directory.appendingPathComponent("Design Review.mp4"))

        let reusedURL = try await cache.localURL(for: recording, meetingID: "meeting-c")

        XCTAssertNil(reusedURL)
    }

    func testClearRemovesManagedAndLegacyDownloads() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let cache = GoogleMeetDownloadCache(directory: directory)
        let recording = recording(id: "drive-file-3", name: "Managed.mp4", size: 2)
        let temporaryFile = directory.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try Data([1, 2]).write(to: temporaryFile)
        _ = try await cache.store(temporaryURL: temporaryFile, recording: recording, meetingID: "meeting-d")
        try Data([3, 4, 5]).write(to: directory.appendingPathComponent("Legacy.mp4"))

        let deleted = try await cache.clear()

        XCTAssertEqual(deleted.fileCount, 2)
        XCTAssertEqual(deleted.totalBytes, 5)
        let remaining = try await cache.summary()
        XCTAssertEqual(remaining, .empty)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhisperKillerCacheTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func recording(id: String, name: String, size: Int64) -> GoogleDriveRecording {
        GoogleDriveRecording(
            id: id,
            name: name,
            mimeType: "video/mp4",
            modifiedTime: nil,
            sizeBytes: size,
            webViewLink: nil
        )
    }
}
