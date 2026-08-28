import SwiftUI

struct AIChatWindowView: View {
    @EnvironmentObject var appState: AppState
    @State private var draft = ""
    @FocusState private var isInputFocused: Bool

    private var selectedConversation: AIChatConversation? {
        appState.selectedAIChatConversation
    }

    var body: some View {
        ZStack {
            VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                .ignoresSafeArea()

            HStack(spacing: 0) {
                AIChatSidebar()
                    .frame(width: 210)

                Divider()

                VStack(spacing: 0) {
                    AIChatHeader(conversation: selectedConversation)
                    Divider()
                    AIChatMessageList(
                        messages: selectedConversation?.chatMessages ?? [],
                        hasAttachedContext: !(selectedConversation?.attachments.isEmpty ?? true)
                    )
                    AIChatAttachmentShelf(attachments: selectedConversation?.attachments ?? [])
                    Divider()
                    AIChatComposer(draft: $draft, isInputFocused: $isInputFocused)
                }
            }
        }
        .frame(minWidth: 680, minHeight: 460)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("AI Chat")
                    .font(SW.titleFont)
            }
        }
        .onAppear {
            appState.ensureSelectedAIChatConversation()
            appState.refreshAIChatModelsIfNeeded(force: true)
        }
    }
}

private struct AIChatSidebar: View {
    @EnvironmentObject var appState: AppState
    @State private var isShowingRecentItems = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                appState.createAIChatConversation()
            } label: {
                Label(L.tr("New Chat", "Новый чат"), systemImage: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(SW.accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: SW.radiusSmall, style: .continuous))
            }
            .buttonStyle(.swPlainInteractive)

            VStack(alignment: .leading, spacing: 6) {
                Text(L.tr("CHATS", "ЧАТЫ"))
                    .font(SW.labelFont)
                    .foregroundStyle(SW.secondaryText)

                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(appState.aiChatConversations) { conversation in
                            AIChatConversationRow(conversation: conversation)
                        }
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text(L.tr("ATTACH", "ПРИКРЕПИТЬ"))
                    .font(SW.labelFont)
                    .foregroundStyle(SW.secondaryText)

                AIChatAttachButton(
                    title: L.tr("Latest transcript", "Последняя транскрипция"),
                    icon: "text.quote",
                    action: appState.attachLatestTranscriptionToAIChat
                )
                AIChatAttachButton(
                    title: L.tr("Live translation", "Live-перевод"),
                    icon: "captions.bubble",
                    action: appState.attachLiveTranslationToAIChat
                )

                if !appState.history.isEmpty {
                    Button {
                        isShowingRecentItems.toggle()
                    } label: {
                        AIChatSidebarActionLabel(
                            title: L.tr("Recent items", "Недавние"),
                            icon: "clock",
                            trailingIcon: "chevron.down"
                        )
                    }
                    .buttonStyle(.swPlainInteractive)
                    .popover(isPresented: $isShowingRecentItems, arrowEdge: .trailing) {
                        AIChatRecentItemsPopover(isPresented: $isShowingRecentItems)
                    }
                }

                if let error = appState.aiChatAttachmentError, !error.isEmpty {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 9))
                        .foregroundStyle(SW.warning)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
    }
}

private struct AIChatRecentItemsPopover: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool

    var body: some View {
        ScrollView {
            LazyVStack(spacing: SW.spacingXS) {
                ForEach(appState.history.prefix(8), id: \.entryId) { entry in
                    Button {
                        appState.attachHistoryEntryToAIChat(entry)
                        isPresented = false
                    } label: {
                        Text(AIChatRecentItemLabel.text(for: entry))
                            .font(SW.compactFont)
                            .foregroundStyle(SW.primaryText)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.swPlainInteractive)
                }
            }
            .padding(SW.spacingS)
        }
        .frame(width: 320)
        .frame(maxHeight: 280)
        .fixedSize(horizontal: false, vertical: true)
    }
}

enum AIChatRecentItemLabel {
    private static let previewCharacterLimit = 42

    static func text(for entry: TranscriptionHistoryEntry) -> String {
        let preview = [entry.summaryText, entry.processedText, entry.rawText]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })?
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ") ?? ""

        let modeName = entry.modeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let time = entry.date.formatted(date: .omitted, time: .shortened)
        let context = [modeName, time]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")

        guard !preview.isEmpty else { return context }

        let clippedPreview = preview.count > previewCharacterLimit
            ? "\(preview.prefix(previewCharacterLimit))…"
            : preview
        return context.isEmpty ? clippedPreview : "\(context) · \(clippedPreview)"
    }
}

private struct AIChatConversationRow: View {
    @EnvironmentObject var appState: AppState
    let conversation: AIChatConversation

    private var isSelected: Bool {
        appState.settings.selectedAIChatConversationID == conversation.id
    }

    var body: some View {
        Button {
            appState.selectAIChatConversation(conversation.id)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(conversation.displayTitle)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                Text(L.aiChatMessageCount(conversation.chatMessages.count))
                    .font(.system(size: 10))
                    .foregroundStyle(SW.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(isSelected ? SW.accent.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: SW.radiusSmall, style: .continuous))
        }
        .buttonStyle(.swPlainInteractive)
    }
}

private struct AIChatAttachButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AIChatSidebarActionLabel(title: title, icon: icon)
        }
        .buttonStyle(.swPlainInteractive)
    }
}

private struct AIChatSidebarActionLabel: View {
    let title: String
    let icon: String
    var trailingIcon: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
                .frame(width: 16, height: 20, alignment: .center)

            Text(title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 4)

            if let trailingIcon {
                Image(systemName: trailingIcon)
                    .font(.system(size: 7, weight: .semibold))
                    .frame(width: 10, height: 16, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct AIChatHeader: View {
    @EnvironmentObject var appState: AppState
    let conversation: AIChatConversation?

    var body: some View {
        HStack(spacing: 10) {
            Text(conversation?.displayTitle ?? "AI Chat")
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .layoutPriority(1)

            Spacer(minLength: 0)

            AIChatModelMenu()

            Button {
                appState.refreshAIChatModelsIfNeeded(force: true)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .background(SW.rowBackground)
                    .clipShape(RoundedRectangle(cornerRadius: SW.radiusSmall, style: .continuous))
            }
            .buttonStyle(.swPlainInteractive)
            .disabled(appState.isLoadingAIChatModels || !appState.settings.hasOpenAIAPIKey)
            .accessibilityLabel(L.tr("Refresh OpenAI models", "Обновить модели OpenAI"))
            .help(L.tr("Refresh OpenAI models", "Обновить модели OpenAI"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

private struct AIChatModelMenu: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Menu {
            if appState.isLoadingAIChatModels {
                Text(L.tr("Loading models...", "Загружаю модели..."))
            }

            if !appState.settings.hasOpenAIAPIKey {
                Text(L.tr("Add an OpenAI API key in Settings.", "Добавьте OpenAI API key в настройках."))
            }

            ForEach(modelList, id: \.self) { model in
                Button {
                    appState.setAIChatModel(model)
                } label: {
                    HStack {
                        Text(model)
                        if appState.settings.selectedAIChatModel == model {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: appState.isLoadingAIChatModels ? "arrow.triangle.2.circlepath" : "cpu")
                    .font(.system(size: 10, weight: .semibold))
                Text(appState.settings.selectedAIChatModel)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
            }
            .frame(maxWidth: 190)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(SW.rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: SW.radiusSmall, style: .continuous))
            .swInteractiveHover()
        }
        .menuStyle(.borderlessButton)
    }

    private var modelList: [String] {
        let models = appState.availableAIChatModels
        if models.isEmpty {
            return [appState.settings.selectedAIChatModel].filter { !$0.isEmpty }
        }
        return models
    }
}

private struct AIChatMessageList: View {
    let messages: [AIChatMessage]
    let hasAttachedContext: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if messages.isEmpty {
                        AIChatEmptyState(hasAttachedContext: hasAttachedContext)
                    } else {
                        ForEach(messages) { message in
                            AIChatMessageRow(message: message)
                                .id(message.id)
                        }
                    }
                }
                .frame(maxWidth: SW.readableContentMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, SW.spacingXL)
                .padding(.vertical, SW.spacingL)
            }
            .onChange(of: messages) { _, newMessages in
                guard let last = newMessages.last else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }
}

private struct AIChatEmptyState: View {
    let hasAttachedContext: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(SW.tertiaryText)
            Text(
                hasAttachedContext
                    ? L.tr(
                        "Context is attached. Ask a question about it.",
                        "Контекст прикреплён. Задайте вопрос по нему."
                    )
                    : L.tr(
                        "Ask, summarize, translate, or attach recent transcript context.",
                        "Спросите, суммаризируйте, переведите или прикрепите недавнюю транскрипцию."
                    )
            )
                .font(SW.compactFont)
                .foregroundStyle(SW.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
    }
}

private struct AIChatAttachmentShelf: View {
    @EnvironmentObject var appState: AppState
    let attachments: [AIChatMessage]
    @State private var expandedAttachmentID: UUID?

    var body: some View {
        if !attachments.isEmpty {
            VStack(alignment: .leading, spacing: SW.spacingS) {
                HStack(spacing: SW.spacingXS) {
                    Text(L.tr("CONTEXT", "КОНТЕКСТ"))
                        .font(SW.labelFont)
                        .foregroundStyle(SW.secondaryText)

                    Text("\(attachments.count)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(SW.secondaryText)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(SW.rowBackground)
                        .clipShape(Capsule())
                }

                ScrollView {
                    LazyVStack(spacing: SW.spacingXS) {
                        ForEach(attachments) { attachment in
                            AIChatAttachmentRow(
                                attachment: attachment,
                                isExpanded: expandedAttachmentID == attachment.id,
                                onToggle: {
                                    withAnimation(.easeInOut(duration: 0.16)) {
                                        expandedAttachmentID = expandedAttachmentID == attachment.id
                                            ? nil
                                            : attachment.id
                                    }
                                },
                                onRemove: {
                                    appState.removeAIChatAttachment(attachment.id)
                                }
                            )
                        }
                    }
                }
                .frame(maxHeight: 220)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: SW.readableContentMaxWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, SW.spacingXL)
            .padding(.top, SW.spacingS)
            .padding(.bottom, SW.spacingM)
            .background(Color.primary.opacity(0.018))
            .overlay(alignment: .top) {
                Divider()
            }
            .onChange(of: attachments.map(\.id)) { _, ids in
                if let expandedAttachmentID, !ids.contains(expandedAttachmentID) {
                    self.expandedAttachmentID = nil
                }
            }
        }
    }
}

private struct AIChatAttachmentRow: View {
    let attachment: AIChatMessage
    let isExpanded: Bool
    let onToggle: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: SW.spacingS) {
                Button(action: onToggle) {
                    HStack(spacing: SW.spacingS) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(SW.secondaryText)
                            .frame(width: 10, height: 18)

                        Image(systemName: "paperclip")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(SW.secondaryText)
                            .frame(width: 14, height: 18)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(attachment.attachmentTitle ?? L.tr("Attached context", "Прикреплённый контекст"))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(SW.primaryText)
                                .lineLimit(1)

                            if !isExpanded {
                                Text(attachment.attachmentText)
                                    .font(.system(size: 10))
                                    .foregroundStyle(SW.secondaryText)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }

                        Spacer(minLength: SW.spacingS)

                        Text(attachment.date.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 9))
                            .foregroundStyle(SW.tertiaryText)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.swPlainInteractive)

                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(SW.secondaryText)
                        .frame(width: 22, height: 22)
                        .background(SW.rowBackground)
                        .clipShape(RoundedRectangle(cornerRadius: SW.radiusSmall, style: .continuous))
                }
                .buttonStyle(.swPlainInteractive)
                .accessibilityLabel(L.tr("Remove attached context", "Удалить прикреплённый контекст"))
                .help(L.tr("Remove attached context", "Удалить прикреплённый контекст"))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)

            if isExpanded {
                Divider()
                    .padding(.horizontal, 10)

                Text(attachment.attachmentText)
                    .font(.system(size: 11))
                    .foregroundStyle(SW.primaryText)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(SW.rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: SW.radiusMedium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SW.radiusMedium, style: .continuous)
                .strokeBorder(isExpanded ? SW.accent.opacity(0.28) : SW.border, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct AIChatComposer: View {
    @EnvironmentObject var appState: AppState
    @Binding var draft: String
    @FocusState.Binding var isInputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            composerStatus

            HStack(alignment: .bottom, spacing: 8) {
                Button {
                    appState.toggleAIChatVoiceMessage()
                } label: {
                    Image(systemName: appState.isAIChatVoiceRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .foregroundStyle(appState.isAIChatVoiceRecording ? Color.white : SW.primaryText)
                        .background(appState.isAIChatVoiceRecording ? SW.danger : SW.rowBackground)
                        .clipShape(RoundedRectangle(cornerRadius: SW.radiusSmall, style: .continuous))
                }
                .buttonStyle(.swPlainInteractive)
                .disabled(!canToggleVoice)
                .accessibilityLabel(voiceActionLabel)
                .help(voiceActionLabel)

                TextField(L.tr("Ask about transcripts...", "Спросить по транскрипциям..."), text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($isInputFocused)
                    .lineLimit(1...4)
                    .onSubmit(sendDraft)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(SW.rowBackground)
                    .clipShape(RoundedRectangle(cornerRadius: SW.radiusSmall, style: .continuous))

                Button(action: sendDraft) {
                    Image(systemName: appState.isAIChatSending ? "hourglass" : "paperplane.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .foregroundStyle(canSend ? SW.accent : SW.secondaryText)
                        .background(SW.rowBackground)
                        .clipShape(RoundedRectangle(cornerRadius: SW.radiusSmall, style: .continuous))
                }
                .buttonStyle(.swPlainInteractive)
                .disabled(!canSend)
                .accessibilityLabel(sendActionLabel)
                .help(sendActionLabel)
            }
        }
        .padding(14)
    }

    @ViewBuilder
    private var composerStatus: some View {
        if !appState.settings.hasOpenAIAPIKey {
            Label(
                L.tr("Add an OpenAI API key in Settings to send messages.", "Добавьте OpenAI API key в настройках, чтобы отправлять сообщения."),
                systemImage: "key"
            )
            .font(.system(size: 10))
            .foregroundStyle(SW.warning)
        } else if let error = appState.aiChatError, !error.isEmpty {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.system(size: 10))
                .foregroundStyle(SW.warning)
                .lineLimit(2)
        } else if appState.isAIChatVoiceRecording {
            Label(L.tr("Recording voice message...", "Запись голосового сообщения..."), systemImage: "waveform")
                .font(.system(size: 10))
                .foregroundStyle(SW.danger)
        } else if appState.isAIChatSending {
            Label(L.tr("Sending message...", "Отправка сообщения..."), systemImage: "hourglass")
                .font(.system(size: 10))
                .foregroundStyle(SW.secondaryText)
        }
    }

    private var canSend: Bool {
        appState.settings.hasOpenAIAPIKey
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !appState.isAIChatSending
    }

    private var canToggleVoice: Bool {
        appState.isAIChatVoiceRecording
            || (appState.settings.hasOpenAIAPIKey && !appState.isAIChatSending)
    }

    private var voiceActionLabel: String {
        appState.isAIChatVoiceRecording
            ? L.tr("Stop voice recording", "Остановить запись")
            : L.tr("Record voice message", "Записать голосовое сообщение")
    }

    private var sendActionLabel: String {
        appState.isAIChatSending
            ? L.tr("Sending message", "Сообщение отправляется")
            : L.tr("Send message", "Отправить сообщение")
    }

    private func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend, !text.isEmpty else { return }
        draft = ""
        isInputFocused = false
        appState.sendAIChatMessage(text)
    }
}

private struct AIChatMessageRow: View {
    let message: AIChatMessage

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        HStack {
            if isUser {
                Spacer(minLength: 64)
            }

            Text(message.content)
                .font(.system(size: 12))
                .foregroundStyle(SW.primaryText)
                .textSelection(.enabled)
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(isUser ? SW.accent.opacity(0.13) : Color.primary.opacity(0.055))
                .clipShape(RoundedRectangle(cornerRadius: SW.radiusMedium, style: .continuous))
                .frame(maxWidth: 430, alignment: isUser ? .trailing : .leading)

            if !isUser {
                Spacer(minLength: 64)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
}
