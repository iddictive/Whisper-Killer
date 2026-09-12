import Foundation
import XCTest
@testable import WhisperKiller

final class AppSettingsDecodingTests: XCTestCase {
    func testRetiredTranscriptionEngineFallsBackWithoutResettingSettings() throws {
        let data = Data(
            #"{"apiKey":"sentinel-key","engineType":"Experimental GigaAM Russian","setupCompleted":true}"#.utf8
        )

        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(settings.engineType, .cloud)
        XCTAssertEqual(settings.apiKey, "sentinel-key")
        XCTAssertTrue(settings.setupCompleted)
    }
}
