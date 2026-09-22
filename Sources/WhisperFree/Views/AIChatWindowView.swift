import SwiftUI

struct AIChatWindowView: View {
    @EnvironmentObject var appState: AppState
    @State private var drafts: [UUID: String] = [:]
    @State private var isShowingSources = false
    @FocusState private var isInputFocused: Bool

    private var selectedConversation: AIChatConversation? {
        appState.selectedAIChatConversation
    }

    private var draft: Binding<String> {
        Binding(get: { selectedConversation.flatMap { drafts[$0.id] } ?? "" }, set: { value in
            if let id = selectedConversation?.id { drafts[id] = value }
        })
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
                    AIChatMessageList(
                        messages: selectedConversation?.chatMessages ?? [],
                        hasAttachedContext: !(selectedConversation?.attachments.isEmpty ?? true),
                        onChooseSources: { isShowingSources = true },
                        onPrompt: { prompt in
                            if draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                draft.wrappedValue = prompt
                            } else {
                                draft.wrappedValue += "\n\n" + prompt
                            }
                            isInputFocused = true
                        }
                    )
                    AIChatComposer(draft: draft, onChooseSources: { isShowingSources = true }, isInputFocused: $isInputFocused)
                }
            }
        }
        .frame(minWidth: 680, minHeight: 460)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("AI Chat")
                    .font(SW.titleFont)
            }
            ToolbarItem(placement: .primaryAction) {
                AIChatModelMenu()
            }
        }
        .sheet(isPresented: $isShowingSources, onDismiss: { isInputFocused = true }) {
            AIChatSourcePicker()
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

            Spacer(minLength: 0)
        }
        .padding(12)
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
            Divider()
            Button(L.tr("Refresh models", "Обновить модели")) {
                appState.refreshAIChatModelsIfNeeded(force: true)
            }
            .disabled(appState.isLoadingAIChatModels || !appState.settings.hasOpenAIAPIKey)
        } label: {
            Text(appState.settings.selectedAIChatModel)
                .font(SW.compactFont)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
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
    let onChooseSources: () -> Void
    let onPrompt: (String) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if messages.isEmpty {
                        AIChatEmptyState(hasAttachedContext: hasAttachedContext, onChooseSources: onChooseSources, onPrompt: onPrompt)
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
    let onChooseSources: () -> Void
    let onPrompt: (String) -> Void

    var body: some View {
        VStack(spacing: SW.spacingL) {
            Text(hasAttachedContext
                 ? L.tr("What would you like to find out?", "Что хотите узнать?")
                 : L.tr("Work with your transcripts", "Поработаем с расшифровками"))
                .font(.system(size: 18, weight: .semibold))
                .multilineTextAlignment(.center)
            if hasAttachedContext {
                ViewThatFits(in: .horizontal) {
                    HStack { suggestions }
                    VStack { suggestions }
                }
            } else {
                Button(action: onChooseSources) {
                    Label(L.tr("Choose transcripts", "Выбрать расшифровки"), systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    private var suggestions: some View {
        Group {
            Button(L.tr("Summarize", "Кратко")) {
                onPrompt(L.tr("Summarize the attached transcripts, highlighting the key points.",
                              "Кратко изложи главное из прикреплённых расшифровок."))
            }
            Button(L.tr("Action items", "Задачи")) {
                onPrompt(L.tr("Extract action items, owners and deadlines from the attached transcripts. Flag anything not specified.",
                              "Выдели задачи, ответственных и сроки из расшифровок. Отметь, где данных не хватает."))
            }
            Button(L.tr("Key takeaways", "Выводы")) {
                onPrompt(L.tr("What are the key decisions and open questions in the attached transcripts?",
                              "Какие решения приняты и какие вопросы остались открытыми в расшифровках?"))
            }
        }
        .buttonStyle(.bordered)
    }
}

private struct AIChatAttachmentShelf: View {
    let attachments: [AIChatMessage]

    var body: some View {
        if !attachments.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: SW.spacingS) {
                    ForEach(attachments) { attachment in
                        AIChatAttachmentChip(attachment: attachment)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AIChatAttachmentChip: View {
    @EnvironmentObject var appState: AppState
    let attachment: AIChatMessage
    @State private var isShowingPreview = false

    private var source: TranscriptionHistoryEntry? {
        appState.history.first { attachment.attachmentSourceID == "history:\($0.entryId.uuidString)" }
    }

    private var title: String {
        source.map { AIChatSources.title(for: $0) }
            ?? attachment.attachmentTitle
            ?? L.tr("Transcript", "Расшифровка")
    }

    var body: some View {
        HStack(spacing: SW.spacingXS) {
            Button {
                isShowingPreview.toggle()
            } label: {
                Label(title, systemImage: source?.isFromFileImport == true ? "doc.text" : "text.quote")
                    .font(SW.compactFont)
                    .lineLimit(1)
                    .frame(maxWidth: 220, alignment: .leading)
                    .padding(.vertical, SW.spacingS)
            }
            .buttonStyle(.swPlainInteractive)
            .help(L.tr("Preview source", "Просмотреть источник"))
            .popover(isPresented: $isShowingPreview) {
                ScrollView {
                    VStack(alignment: .leading, spacing: SW.spacingM) {
                        if let source {
                            HStack {
                                if source.isFromFileImport && source.audioFilePath != nil {
                                    Text(AIChatSources.title(for: source)).lineLimit(1)
                                }
                                Spacer()
                                Text(source.date.formatted(date: .abbreviated, time: .shortened))
                            }
                            .font(SW.compactFont)
                            .foregroundStyle(SW.secondaryText)
                        }
                        Text(attachment.attachmentText)
                            .font(.system(size: 13))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(SW.spacingL)
                }
                .frame(width: 420)
                .frame(maxHeight: 320)
            }
            Button {
                appState.removeAIChatAttachment(attachment.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .frame(width: 24, height: 28)
            }
            .buttonStyle(.swPlainInteractive)
            .accessibilityLabel(L.tr("Remove source", "Убрать источник"))
            .help(L.tr("Remove source", "Убрать источник"))
        }
        .padding(.leading, SW.spacingS)
        .background(SW.rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: SW.radiusMedium))
    }
}

private struct AIChatComposer: View {
    @EnvironmentObject var appState: AppState
    @Binding var draft: String
    let onChooseSources: () -> Void
    @FocusState.Binding var isInputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: SW.spacingS) {
            composerStatus
            if let error = appState.aiChatAttachmentError {
                Text(error).font(SW.compactFont).foregroundStyle(SW.warning)
            }
            VStack(alignment: .leading, spacing: SW.spacingM) {
                AIChatAttachmentShelf(attachments: appState.selectedAIChatConversation?.attachments ?? [])
                TextField(L.tr("Ask about transcripts…", "Спросить по расшифровкам…"), text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isInputFocused)
                    .lineLimit(2...7)
                    .onSubmit(sendDraft)
                    .accessibilityLabel(L.tr("Message", "Сообщение"))
                HStack(spacing: SW.spacingS) {
                    Button(action: onChooseSources) {
                        Label(L.tr("Transcripts", "Расшифровки"), systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    Menu {
                        Button(L.tr("Latest transcript", "Последняя расшифровка"), action: appState.attachLatestTranscriptionToAIChat)
                        Button(L.tr("Live translation", "Live-перевод"), action: appState.attachLiveTranslationToAIChat)
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityLabel(L.tr("Other sources", "Другие источники"))
                    Spacer(minLength: SW.spacingS)
                    voiceButton
                    Button(action: sendDraft) {
                        Image(systemName: appState.isAIChatSending ? "hourglass" : "arrow.up")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 24, height: 26)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSend)
                    .accessibilityLabel(sendActionLabel)
                    .help(sendActionLabel)
                }
            }
            .padding(SW.spacingM)
            .background(SW.rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: SW.radiusLarge))
        }
        .frame(maxWidth: SW.readableContentMaxWidth)
        .frame(maxWidth: .infinity)
        .padding(SW.spacingL)
    }

    private var voiceButton: some View {
        Button {
            appState.toggleAIChatVoiceMessage()
        } label: {
            Image(systemName: appState.isAIChatVoiceRecording ? "stop.fill" : "mic")
                .font(.system(size: 13, weight: .medium))
                .frame(width: 30, height: 30)
                .foregroundStyle(appState.isAIChatVoiceRecording ? SW.danger : SW.primaryText)
        }
        .buttonStyle(.swPlainInteractive)
        .disabled(!canToggleVoice)
        .accessibilityLabel(voiceActionLabel)
        .help(voiceActionLabel)
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
        isInputFocused = true
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

            Text(message.role == .assistant ? (try? AttributedString(markdown: message.content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(message.content) : AttributedString(message.content))
                .font(.system(size: 13))
                .foregroundStyle(SW.primaryText)
                .textSelection(.enabled)
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(isUser ? SW.accent.opacity(0.13) : Color.primary.opacity(0.055))
                .clipShape(RoundedRectangle(cornerRadius: SW.radiusMedium, style: .continuous))
                .frame(maxWidth: isUser ? 480 : .infinity, alignment: isUser ? .trailing : .leading)
                .contextMenu {
                    Button(L.tr("Copy", "Скопировать")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.content, forType: .string)
                    }
                }

            if !isUser {
                Spacer(minLength: 64)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
}
