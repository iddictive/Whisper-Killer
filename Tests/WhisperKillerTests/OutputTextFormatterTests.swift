import XCTest
@testable import WhisperKiller

final class OutputTextFormatterTests: XCTestCase {
    func testTextCasingLowercaseRemovesCapitals() {
        var settings = AppSettings()
        settings.textCasing = .lowercase
        let input = "Привет, Мир! Hello WORLD!"
        let result = OutputTextFormatter.apply(to: input, settings: settings)
        XCTAssertEqual(result, "привет, мир! hello world!")
    }

    func testTextCasingUppercaseCaps() {
        var settings = AppSettings()
        settings.textCasing = .uppercase
        let input = "Привет, мир! Hello world!"
        let result = OutputTextFormatter.apply(to: input, settings: settings)
        XCTAssertEqual(result, "ПРИВЕТ, МИР! HELLO WORLD!")
    }

    func testTextCasingSentenceCase() {
        var settings = AppSettings()
        settings.textCasing = .sentenceCase
        let input = "привет мир. как дела? всё супер! nice to meet you."
        let result = OutputTextFormatter.apply(to: input, settings: settings)
        XCTAssertEqual(result, "Привет мир. Как дела? Всё супер! Nice to meet you.")
    }

    func testTextCasingTitleCase() {
        var settings = AppSettings()
        settings.textCasing = .titleCase
        let input = "привет мир hello world"
        let result = OutputTextFormatter.apply(to: input, settings: settings)
        XCTAssertEqual(result, "Привет Мир Hello World")
    }

    func testStripAllPunctuationRemovesPunctuation() {
        var settings = AppSettings()
        settings.enablePunctuation = false
        let input = "Привет, мир! Как дела? (Всё отлично), «работает» на 100% — без проблем."
        let result = OutputTextFormatter.apply(to: input, settings: settings)
        XCTAssertEqual(result, "Привет мир Как дела Всё отлично работает на 100 без проблем")
    }

    func testStripAllPunctuationPreservesDecimals() {
        var settings = AppSettings()
        settings.enablePunctuation = false
        let input = "Версия 2.0 и цена 10,5 рублей."
        let result = OutputTextFormatter.apply(to: input, settings: settings)
        XCTAssertEqual(result, "Версия 2.0 и цена 10,5 рублей")
    }

    func testSelectiveRemovalCommas() {
        var settings = AppSettings()
        settings.enablePunctuation = true
        settings.removeCommas = true
        let input = "Раз, два, три, четыре!"
        let result = OutputTextFormatter.apply(to: input, settings: settings)
        XCTAssertEqual(result, "Раз два три четыре!")
    }

    func testSelectiveRemovalPeriods() {
        var settings = AppSettings()
        settings.enablePunctuation = true
        settings.removePeriods = true
        let input = "Привет, мир. Как дела... Конец."
        let result = OutputTextFormatter.apply(to: input, settings: settings)
        XCTAssertEqual(result, "Привет, мир Как дела Конец")
    }

    func testSelectiveRemovalQuestionAndExclamation() {
        var settings = AppSettings()
        settings.enablePunctuation = true
        settings.removeQuestionExclamation = true
        let input = "Что?! Где? Когда! Вот так."
        let result = OutputTextFormatter.apply(to: input, settings: settings)
        XCTAssertEqual(result, "Что Где Когда Вот так.")
    }

    func testSelectiveRemovalHyphensAndDashes() {
        var settings = AppSettings()
        settings.enablePunctuation = true
        settings.removeHyphensDashes = true
        let input = "Кое-что — это супер-вещь."
        let result = OutputTextFormatter.apply(to: input, settings: settings)
        XCTAssertEqual(result, "Кое что это супер вещь.")
    }

    func testCombinedLowercaseAndNoPunctuation() {
        var settings = AppSettings()
        settings.textCasing = .lowercase
        settings.enablePunctuation = false
        let input = "Привет, Мир! Как дела? Всё Супер."
        let result = OutputTextFormatter.apply(to: input, settings: settings)
        XCTAssertEqual(result, "привет мир как дела всё супер")
    }

    func testSettingsRoundTripWithFormattingOptions() throws {
        var settings = AppSettings()
        settings.textCasing = .lowercase
        settings.enablePunctuation = false
        settings.removePeriods = true
        settings.removeCommas = true
        settings.removeQuestionExclamation = true
        settings.removeHyphensDashes = true
        settings.removeQuotesBrackets = true
        settings.removeColonsSemicolons = true

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.textCasing, .lowercase)
        XCTAssertFalse(decoded.enablePunctuation)
        XCTAssertTrue(decoded.removePeriods)
        XCTAssertTrue(decoded.removeCommas)
        XCTAssertTrue(decoded.removeQuestionExclamation)
        XCTAssertTrue(decoded.removeHyphensDashes)
        XCTAssertTrue(decoded.removeQuotesBrackets)
        XCTAssertTrue(decoded.removeColonsSemicolons)
    }
}
