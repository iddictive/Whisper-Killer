import SwiftUI

enum TranscriptionEnginePickerPresentation {
    case settingsSegmented
    case setupGrid
}

struct TranscriptionEnginePicker: View {
    @Binding private var selection: TranscriptionEngineType

    private let presentation: TranscriptionEnginePickerPresentation
    private let isReady: (TranscriptionEngineType) -> Bool
    private let onSelection: (TranscriptionEngineType) -> Void

    init(
        selection: Binding<TranscriptionEngineType>,
        presentation: TranscriptionEnginePickerPresentation,
        isReady: @escaping (TranscriptionEngineType) -> Bool = { _ in false },
        onSelection: @escaping (TranscriptionEngineType) -> Void = { _ in }
    ) {
        _selection = selection
        self.presentation = presentation
        self.isReady = isReady
        self.onSelection = onSelection
    }

    var body: some View {
        switch presentation {
        case .settingsSegmented:
            settingsSegmentedPicker
        case .setupGrid:
            setupGridPicker
        }
    }

    private var settingsSegmentedPicker: some View {
        HStack(spacing: 0) {
            ForEach(TranscriptionEngineType.allCases, id: \.self) { type in
                settingsOption(type)

                if type != TranscriptionEngineType.allCases.last {
                    Divider()
                        .frame(height: 18)
                }
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var setupGridPicker: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2),
            spacing: 10
        ) {
            ForEach(TranscriptionEngineType.allCases, id: \.self) { type in
                setupOption(type)
            }
        }
    }

    private func settingsOption(_ type: TranscriptionEngineType) -> some View {
        let selected = type == selection

        return Button {
            select(type)
        } label: {
            Text(type.localizedShortTitle)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, minHeight: 30)
                .padding(.horizontal, 6)
                .foregroundStyle(selected ? .primary : .secondary)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(selected ? Color(nsColor: .controlBackgroundColor).opacity(0.92) : Color.clear)
                )
        }
        .buttonStyle(.swPlainInteractive)
        .disabled(!isSelectable(type))
    }

    private func setupOption(_ type: TranscriptionEngineType) -> some View {
        let selected = type == selection

        return Button {
            withAnimation(.spring(response: 0.3)) {
                select(type)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: setupIcon(for: type))
                    .font(.system(size: 13))
                Text(setupTitle(for: type))
                    .font(.system(size: 12, weight: .semibold))
                if isReady(type) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 11)
            .background(selected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.045))
            .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: 1.5)
            )
        }
        .buttonStyle(.swPlainInteractive)
        .disabled(!isSelectable(type))
    }

    private func select(_ type: TranscriptionEngineType) {
        selection = type
        onSelection(type)
    }

    private func isSelectable(_ type: TranscriptionEngineType) -> Bool {
        type != .parakeet || ParakeetTranscriber.isAppleSilicon
    }

    private func setupTitle(for type: TranscriptionEngineType) -> String {
        switch type {
        case .cloud: return "Cloud"
        case .local: return "Whisper"
        case .qwenASR: return "Qwen"
        case .parakeet: return "Parakeet"
        }
    }

    private func setupIcon(for type: TranscriptionEngineType) -> String {
        switch type {
        case .cloud: return "cloud.fill"
        case .local, .qwenASR, .parakeet: return type.icon
        }
    }
}
