import XCTest
@testable import WhisperKiller

final class AIChatAttachmentTests: XCTestCase {
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
