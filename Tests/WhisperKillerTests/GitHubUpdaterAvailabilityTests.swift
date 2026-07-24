import Foundation
import XCTest
@testable import WhisperKiller

final class GitHubUpdaterAvailabilityTests: XCTestCase {
    func testInstalledProductionBundleCanUseUpdater() {
        XCTAssertTrue(
            GitHubUpdater.isAvailable(
                bundleIdentifier: "com.whisperkiller.app",
                bundleURL: URL(fileURLWithPath: "/Applications/WhisperKiller.app")
            )
        )
    }

    func testDevelopmentBundleCannotUseUpdater() {
        XCTAssertFalse(
            GitHubUpdater.isAvailable(
                bundleIdentifier: "com.whisperkiller.app.dev",
                bundleURL: URL(fileURLWithPath: "/Users/example/project/.build/dev-runtime/WhisperKiller Dev.app")
            )
        )
    }

    func testTemporaryProductionNamedBundleCannotUseUpdater() {
        XCTAssertFalse(
            GitHubUpdater.isAvailable(
                bundleIdentifier: "com.whisperkiller.app",
                bundleURL: URL(fileURLWithPath: "/private/tmp/WhisperKiller QA.app")
            )
        )
    }
}
