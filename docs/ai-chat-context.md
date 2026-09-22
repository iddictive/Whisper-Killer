# AI Chat Context Contract

## User Story

As a user, I want transcript context to remain visibly separate from chat messages so that I can understand, inspect, replace, and remove what the assistant will use.

## Scope

In scope:

- latest transcript, live translation, and full searchable history sources;
- attachment persistence inside the selected conversation;
- composer attachment chips, source-picker previews, removal, duplicate replacement, and attach-local errors;
- source-picker and composer control hierarchy for transcript selection, suggestions, voice capture, and sending;
- chat title and message-count behavior when context is attached.

Out of scope:

- changing the OpenAI request transport or model-selection flow;
- adding file attachments or drag and drop;
- redesigning ordinary user and assistant message bubbles.

## Surface Contract

The primary object is attached context. Its first visible evidence is a compact,
single-line chip inside the composer. A chip shows its source icon, title, and
remove action; opening it shows a popover with the timestamp and full selectable
text. Attached context never appears as a chat turn.

```text
message history
────────────────────────────────────────
[ 📎 Latest transcript × ] [ 📎 Meeting import × ]
message input
Transcripts   ⋯   microphone   send
```

The source picker opens from the composer and empty state. It searches the full
history, filters voice recordings and imports, and lets the user attach several
sources. A voice row keeps text before its timestamp in both preview states;
expansion reveals more text without repeating a prefix or moving the timestamp
ahead of it. An imported file may keep a filename-and-timestamp header followed
by its distinct transcript body when expanded.

Secondary actions in the picker, empty state, and suggestions share the muted
AI Chat treatment. Composer voice and send actions have matching circular
affordances, and disabled actions remain visually quieter than active actions.

## State And Ownership

| State | Visible result | Owner |
|---|---|---|
| Empty | No attachment chips; the empty state can open the source picker | Message list |
| Attached | Compact chip appears inside the composer, outside the message feed | Composer |
| Chip preview | Popover shows source timestamp and full selectable text | Attachment chip |
| Picker collapsed | Voice text uses at most two lines and its timestamp follows it | Source picker |
| Picker expanded | One source preview is expanded at a time; voice text remains before its timestamp | Source picker |
| Duplicate source | Existing attachment is replaced in place | Conversation model |
| Attach error | A separate line appears above the composer card | Composer attachment state |
| Removed | Attachment is removed from persistence and later requests | Conversation model |
| Sent | Attachments remain available until explicitly removed | Conversation model |

## Implementation Decision

Attachments remain encoded as `AIChatMessage` values for request and storage compatibility, but `attachmentTitle != nil` classifies them as context rather than visible chat turns. `attachmentSourceID` provides stable upsert identity while decoding older stored conversations as `nil`. `AIChatWindowView` owns the composer chips and their popovers; `AIChatSourcePicker` owns full-history search, filtering, and one-at-a-time preview expansion; `AIChatSources` owns source titles, transcript text, and matching.

## Acceptance Criteria

- Attaching context must not create a visible user-message bubble or increment the chat message count.
- Reattaching the same source replaces its existing attachment instead of adding a duplicate.
- Attachment chips remain in the composer and their popovers show the source timestamp and full selectable text.
- The source picker searches the full history, filters voice recordings and imports, and allows more than one source to be attached.
- Expanding one source-picker row collapses the previously expanded row.
- A voice source keeps its text before its timestamp in both picker states; expansion reveals the full text without repeating a preview or title.
- Imported-file rows may retain a filename-and-timestamp header and reveal a distinct transcript body on expansion.
- Picker, empty-state, and suggestion actions use the shared muted secondary treatment; composer voice and send actions remain matched circles, including their disabled appearance.
- Attach-source errors render on their own line above the composer card and must not replace chips, input, or controls.
- Removing an attachment removes it from the stored conversation and subsequent requests.
- Must not change ordinary user/assistant bubble anatomy or the OpenAI message transport.

Reject the result when attachment context returns to the message feed, a chip loses its popover text or timestamp, more than one picker row is expanded, a voice-source timestamp moves ahead of its text or its preview repeats on expansion, an AI Chat secondary action falls back to opaque native bordered chrome, disabled composer actions outweigh active controls, attach errors replace composer controls, or repeated selection creates another attachment for the same source.

## Verification

- Unit-test attachment upsert, replacement, removal, legacy decoding, and visible message count.
- Render the `make dev` window with zero, multiple chips, chip preview, removed, duplicate, and attach-error states.
- Capture the native source picker with the same voice source collapsed and expanded, then capture the composer with muted secondary actions and disabled voice/send controls.
- Confirm the composer remains visible and the message feed contains only real user/assistant turns.
- For a paint-only edit, replay the affected native state and its nearest state change; replay storage, attachment, and error states only when that owner changes.
