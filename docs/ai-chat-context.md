# AI Chat Context Contract

## User Story

As a user, I want transcript context to remain visibly separate from chat messages so that I can understand, inspect, replace, and remove what the assistant will use.

## Scope

In scope:

- latest transcript, live translation, and recent-history attachment sources;
- attachment persistence inside the selected conversation;
- context shelf, collapsed and expanded rows, removal, duplicate replacement, and attach-local errors;
- chat title and message-count behavior when context is attached.

Out of scope:

- changing the OpenAI request transport or model-selection flow;
- adding file attachments or drag and drop;
- redesigning ordinary user and assistant message bubbles.

## Surface Contract

The primary object is attached context. The first visible evidence is a compact context row above the composer. Its stable slots are disclosure indicator, source icon, title, one-line preview, timestamp, and remove action. Full text appears only in the expanded state.

```text
message history
────────────────────────────────────────
Attached context · 2
▸ 📎 Latest transcript   preview…   11:35  ×
▾ 📎 Raw                 preview…   11:29  ×
    full selectable transcript text…
────────────────────────────────────────
microphone  message input             send
```

## State And Ownership

| State | Visible result | Owner |
|---|---|---|
| Empty | Context shelf is omitted | Conversation model |
| Attached | Compact row appears outside the message feed | Context shelf |
| Collapsed | One-line preview; full text hidden | Attachment row |
| Expanded | One row expanded at a time; shared perimeter remains intact | Context shelf |
| Duplicate source | Existing attachment is replaced in place | Conversation model |
| Attach error | Error appears inside the Attach section | Sidebar attach state |
| Removed | Attachment is removed from persistence and later requests | Conversation model |
| Sent | Attachments remain available until explicitly removed | Conversation model |

## Implementation Decision

Attachments remain encoded as `AIChatMessage` values for request and storage compatibility, but `attachmentTitle != nil` classifies them as context rather than visible chat turns. A new optional `attachmentSourceID` provides stable upsert identity while decoding older stored conversations as `nil`. The context shelf owns the only attachment scroll region; expanded rows do not create nested scrollers.

## Acceptance Criteria

- Attaching context must not create a visible user-message bubble or increment the chat message count.
- Reattaching the same source replaces its existing attachment instead of adding a duplicate.
- Collapsed rows show no more than one preview line; expanding one row collapses the previously expanded row.
- Attach-source errors render in the Attach section and must not occupy the composer status slot.
- Removing an attachment removes it from the stored conversation and subsequent requests.
- Must not change ordinary user/assistant bubble anatomy or the OpenAI message transport.

Reject the result when attachment context returns to the message feed, more than one row is expanded, attach errors resize the composer, or repeated selection creates another row for the same source.

## Verification

- Unit-test attachment upsert, replacement, removal, legacy decoding, and visible message count.
- Render the installed macOS window with zero, multiple collapsed, one expanded, removed, duplicate, and attach-error states.
- Confirm the composer remains visible and the message feed contains only real user/assistant turns.
