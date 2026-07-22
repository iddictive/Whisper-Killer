import XCTest
@testable import WhisperKiller

final class LiveTranscriptAssemblerTests: XCTestCase {
    func testInteriorCommonPhraseDoesNotDeleteIncomingPrefixOrMiddle() {
        let merged = LiveTranscriptAssembler.mergeText(
            previous: "We need to ship the release before Friday with QA.",
            incoming: "Today the release before Friday needs final approval."
        )

        XCTAssertNil(merged)
    }

    func testGenuineSuffixPrefixOverlapMergesAtBoundary() {
        let merged = LiveTranscriptAssembler.mergeText(
            previous: "We need to ship the release before Friday.",
            incoming: "The release before Friday needs final approval."
        )

        XCTAssertEqual(merged, "We need to ship the release before Friday. needs final approval.")
    }

    func testBoundaryMergeCountsOnlySpeechTokens() {
        let merged = LiveTranscriptAssembler.mergeText(
            previous: "We ship the release Friday.",
            incoming: "the release Friday ... after QA."
        )

        XCTAssertEqual(merged, "We ship the release Friday. after QA.")
    }

    func testPairDoesNotMergeWhenOnlyOriginalHasBoundaryOverlap() {
        let merged = LiveTranscriptAssembler.merge(
            previous: .init(
                original: "One two three four five.",
                translated: "Один два три четыре пять."
            ),
            incoming: .init(
                original: "Three four five six.",
                translated: "Шесть."
            )
        )

        XCTAssertNil(merged)
    }

    func testPairMergesWhenBothSidesHaveBoundaryOverlap() {
        let merged = LiveTranscriptAssembler.merge(
            previous: .init(
                original: "One two three four five.",
                translated: "Один два три четыре пять."
            ),
            incoming: .init(
                original: "Three four five six.",
                translated: "Три четыре пять шесть."
            )
        )

        XCTAssertEqual(
            merged,
            .init(
                original: "One two three four five. six.",
                translated: "Один два три четыре пять. шесть."
            )
        )
    }

    func testCumulativePairReplacesBothSidesTogether() {
        let merged = LiveTranscriptAssembler.merge(
            previous: .init(original: "One two three.", translated: "Один два три."),
            incoming: .init(
                original: "One two three four five.",
                translated: "Полный новый перевод пяти слов."
            )
        )

        XCTAssertEqual(
            merged,
            .init(
                original: "One two three four five.",
                translated: "Полный новый перевод пяти слов."
            )
        )
    }

    func testNormalizedEqualPairDoesNotReplaceRicherFormatting() {
        let merged = LiveTranscriptAssembler.merge(
            previous: .init(original: "Hello world.", translated: "Привет, мир."),
            incoming: .init(original: "Hello world", translated: "Привет мир")
        )

        XCTAssertEqual(
            merged,
            .init(original: "Hello world.", translated: "Привет, мир.")
        )
    }

    func testDifferentTurnsNeverMergeEvenWithIdenticalPrefix() {
        let previousID = UUID()
        let incomingID = UUID()

        let merged = LiveTranscriptAssembler.merge(
            previous: .init(
                id: previousID,
                pair: .init(original: "Hello world.", translated: "Привет, мир.")
            ),
            incoming: .init(
                id: incomingID,
                pair: .init(original: "Hello world again.", translated: "Снова привет, мир.")
            )
        )

        XCTAssertNil(merged)
    }

    func testLosslessAppendKeepsUnrelatedIncomingText() {
        XCTAssertEqual(
            LiveTranscriptAssembler.appendLosslessly(
                previous: "First complete thought.",
                incoming: "A separate second thought."
            ),
            "First complete thought. A separate second thought."
        )
    }

    func testStreamingChunkRemovesSingleRepeatedBoundaryWord() {
        XCTAssertEqual(
            LiveTranscriptAssembler.appendStreamingChunk(
                previous: "We're going",
                incoming: "going home"
            ),
            "We're going home"
        )
    }

    func testGeneralAppendDoesNotAssumeSingleWordOverlap() {
        XCTAssertEqual(
            LiveTranscriptAssembler.appendLosslessly(
                previous: "It was very",
                incoming: "very useful"
            ),
            "It was very very useful"
        )
    }

    func testRequestGateCoalescesToLatestPendingValue() {
        var gate = CoalescingRequestGate<String>()

        XCTAssertEqual(gate.submit("first"), "first")
        XCTAssertNil(gate.submit("second"))
        XCTAssertNil(gate.submit("latest"))
        XCTAssertEqual(gate.complete(), "latest")
        XCTAssertNil(gate.complete())
    }

    func testRequestGatePreservesPendingRequestsAcrossTurns() {
        var gate = CoalescingRequestGate<String>()

        XCTAssertEqual(gate.submit("old-A", coalescingKey: "old"), "old-A")
        XCTAssertNil(gate.submit("old-B", coalescingKey: "old"))
        XCTAssertNil(gate.submit("new-C", coalescingKey: "new"))
        XCTAssertEqual(gate.complete(), "old-B")
        XCTAssertEqual(gate.complete(), "new-C")
        XCTAssertNil(gate.complete())
    }

    func testSlowRecognitionDefersSilenceTurnRotation() {
        var guardState = LiveSilenceBoundaryGuard()

        guardState.beginRecognition()
        XCTAssertFalse(guardState.shouldRotateTurnOnSilence())

        guardState.endRecognition()
        XCTAssertTrue(guardState.shouldRotateTurnOnSilence())
    }

    func testDraftIsVisibleBeforeTranslationArrives() {
        XCTAssertTrue(
            LiveTranscriptPresentation.shouldShowDraft(
                lastCommittedOriginal: nil,
                currentOriginal: "Current live speech"
            )
        )
    }

    func testCommittedTextIsNotDuplicatedAsDraft() {
        XCTAssertFalse(
            LiveTranscriptPresentation.shouldShowDraft(
                lastCommittedOriginal: "Current live speech",
                currentOriginal: " Current live speech "
            )
        )
    }

    func testBoundedAudioBufferRetainsNewestAudioAndReportsLoss() {
        var buffer = BoundedAudioBuffer(maxByteCount: 5)

        XCTAssertEqual(buffer.append(Data([1, 2, 3])), 0)
        XCTAssertEqual(buffer.append(Data([4, 5, 6, 7])), 2)
        XCTAssertEqual(buffer.consumeAll(), Data([3, 4, 5, 6, 7]))
        XCTAssertEqual(buffer.count, 0)
    }

    func testAudioChunkAssemblerCarriesOnlyConfiguredTail() {
        var assembler = LiveAudioChunkAssembler(overlapByteCount: 3)

        XCTAssertEqual(assembler.makeChunk(from: Data([1, 2, 3, 4])), Data([1, 2, 3, 4]))
        XCTAssertEqual(assembler.makeChunk(from: Data([5, 6])), Data([2, 3, 4, 5, 6]))

        assembler.reset()
        XCTAssertEqual(assembler.makeChunk(from: Data([7])), Data([7]))
    }
}
