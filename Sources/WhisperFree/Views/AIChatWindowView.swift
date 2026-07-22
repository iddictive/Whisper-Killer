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
                    AIChatMessageList(messages: selectedConversation?.messages ?? [])
                    Divider()
                    AIChatComposer(draft: $draft, isInputFocused: $isInputFocused)
                }
            }
        }
        .frame(minWidth: 680, minHeight: 460)
        .toolbarBackground(.visible, for: .windowToolbar)
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
                    Menu {
                        ForEach(appState.history.prefix(8), id: \.entryId) { entry in
                            Button {
                                appState.attachHistoryEntryToAIChat(entry)
                            } label: {
                                Text(entry.modeName)
                            }
                        }
                    } label: {
                        Label(L.tr("Recent items", "Недавние"), systemImage: "clock")
                            .font(.system(size: 11, weight: .medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .swInteractiveHover()
                    }
                    .menuStyle(.borderlessButton)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
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
                Text(L.tr(
                    "\(conversation.messages.count) messages",
                    "Сообщений: \(conversation.messages.count)"
                ))
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
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.swPlainInteractive)
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

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if messages.isEmpty {
                        AIChatEmptyState()
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
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(SW.tertiaryText)
            Text(L.tr("Ask, summarize, translate, or attach recent transcript context.", "Спросите, суммаризируйте, переведите или прикрепите недавнюю транскрипцию."))
                .font(SW.compactFont)
                .foregroundStyle(SW.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
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
    @State private var isAttachmentExpanded = false

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        HStack {
            if isUser {
                Spacer(minLength: 64)
            }

            VStack(alignment: .leading, spacing: 5) {
                if let attachmentTitle = message.attachmentTitle {
                    Button {
                        isAttachmentExpanded.toggle()
                    } label: {
                        HStack(spacing: 5) {
                            Label(attachmentTitle, systemImage: "paperclip")
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: isAttachmentExpanded ? "chevron.up" : "chevron.down")
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(SW.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        isAttachmentExpanded
                            ? L.tr("Collapse attached context", "Свернуть прикреплённый контекст")
                            : L.tr("Expand attached context", "Развернуть прикреплённый контекст")
                    )
                    .help(
                        isAttachmentExpanded
                            ? L.tr("Collapse attached context", "Свернуть прикреплённый контекст")
                            : L.tr("Expand attached context", "Развернуть прикреплённый контекст")
                    )

                    Text(attachmentPreview(title: attachmentTitle))
                        .font(.system(size: 12))
                        .foregroundStyle(SW.primaryText)
                        .lineLimit(isAttachmentExpanded ? nil : 5)
                        .truncationMode(.tail)
                        .textSelection(.enabled)
                } else {
                    Text(message.content)
                        .font(.system(size: 12))
                        .foregroundStyle(SW.primaryText)
                        .textSelection(.enabled)
                }
            }
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

    private func attachmentPreview(title: String) -> String {
        let prefix = "Attached context: \(title)"
        guard message.content.hasPrefix(prefix) else { return message.content }
        return String(message.content.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
