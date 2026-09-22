import XCTest
@testable import WhisperKiller

final class AIChatAttachmentTests: XCTestCase {
    func testLongConversationKeepsSourcesButLimitsOrdinaryTurns() {
        let source = AIChatMessage(role: .user, content: "Full transcript", attachmentTitle: "Meeting")
        let turns = (0..<30).map { AIChatMessage(role: .user, content: "Question \($0)") }
        let request = AIChatService.requestMessages(from: [source] + turns)
        XCTAssertEqual(request.first, source)
        XCTAssertEqual(Array(request.dropFirst()), Array(turns.suffix(24)))
        XCTAssertEqual(AIChatService.requestMessages(from: turns), Array(turns.suffix(24)))
    }

    func testSourceUsesFullTranscriptAndSearchIncludesOlderImportedContent() {
        let entry = TranscriptionHistoryEntry(
            rawText: "Original detail", processedText: "Full transcript with deadline Friday",
            summaryText: "Short summary", modeName: "Meeting", duration: 60,
            engineUsed: "local", isFromFileImport: true, audioFilePath: "/tmp/planning.m4a"
        )
        XCTAssertEqual(AIChatSources.text(for: entry), "Full transcript with deadline Friday")
        XCTAssertEqual(AIChatSources.title(for: entry), "planning.m4a")
        XCTAssertTrue(AIChatSources.matches(entry, query: "FRIDAY", filter: .imports))
        XCTAssertTrue(AIChatSources.matches(entry, query: "planning", filter: .all))
        XCTAssertFalse(AIChatSources.matches(entry, query: "Friday", filter: .voice))
        XCTAssertFalse(AIChatSources.matches(entry, query: "absent", filter: .all))
    }

    func testUpsertReplacesAttachmentFromSameSourceAndPreservesIdentity() {
        let original = AIChatMessage(
            role: .user,
            content: "Attached context: Latest transcript\n\nOld text",
            attachmentTitle: "Latest transcript",
            attachmentSourceID: "history:one"
        )
        var conversation = AIChatConversation(title: "Chat", messages: [original])

        conversation.upsertAttachment(
            AIChatMessage(
                role: .user,
                content: "Attached context: Latest transcript\n\nNew text",
                attachmentTitle: "Latest transcript",
                attachmentSourceID: "history:one"
            )
        )

        XCTAssertEqual(conversation.attachments.count, 1)
        XCTAssertEqual(conversation.attachments.first?.id, original.id)
        XCTAssertEqual(conversation.attachments.first?.attachmentText, "New text")
    }

    func testDifferentSourcesRemainSeparateAttachments() {
        var conversation = AIChatConversation(title: "Chat")

        conversation.upsertAttachment(
            AIChatMessage(
                role: .user,
                content: "Attached context: First\n\nOne",
                attachmentTitle: "First",
                attachmentSourceID: "history:one"
            )
        )
        conversation.upsertAttachment(
            AIChatMessage(
                role: .user,
                content: "Attached context: Second\n\nTwo",
                attachmentTitle: "Second",
                attachmentSourceID: "history:two"
            )
        )

        XCTAssertEqual(conversation.attachments.count, 2)
        XCTAssertTrue(conversation.chatMessages.isEmpty)
    }

    func testRemovingAttachmentPreservesRegularMessages() {
        let attachment = AIChatMessage(
            role: .user,
            content: "Attached context: Latest transcript\n\nContext",
            attachmentTitle: "Latest transcript",
            attachmentSourceID: "latest-transcription"
        )
        let userMessage = AIChatMessage(role: .user, content: "Summarize it")
        var conversation = AIChatConversation(
            title: "Chat",
            messages: [attachment, userMessage]
        )

        conversation.removeAttachment(id: attachment.id)

        XCTAssertTrue(conversation.attachments.isEmpty)
        XCTAssertEqual(conversation.chatMessages, [userMessage])
    }

    func testLegacyAttachmentWithoutSourceIDStillDecodes() throws {
        let message = AIChatMessage(
            role: .user,
            content: "Attached context: Legacy\n\nContext",
            attachmentTitle: "Legacy"
        )
        let encoded = try JSONEncoder().encode(message)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "attachmentSourceID")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(AIChatMessage.self, from: legacyData)

        XCTAssertNil(decoded.attachmentSourceID)
        XCTAssertTrue(decoded.isAttachment)
        XCTAssertEqual(decoded.attachmentText, "Context")
    }
}
