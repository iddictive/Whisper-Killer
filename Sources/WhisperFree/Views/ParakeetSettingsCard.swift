import SwiftUI

struct ParakeetSettingsCard: View {
    @ObservedObject var manager: ParakeetModelManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                statusIcon
                VStack(alignment: .leading, spacing: 3) {
                    Text("Parakeet TDT v3")
                        .font(.system(size: 13, weight: .semibold))
                    statusDetail
                }
                Spacer()
                controls
            }
            Link(
                L.tr("Model details and license", "Описание и лицензия модели"),
                destination: URL(string: "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml")!
            )
            .font(.system(size: 10))
        }
        .padding(10)
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch manager.state {
        case .ready:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
        case .partial, .failed:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
        case .downloading, .validating, .deleting:
            ProgressView().controlSize(.small)
        case .installed, .notInstalled:
            Image(systemName: "arrow.down.circle").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var statusDetail: some View {
        switch manager.state {
        case .downloading(let progress, _):
            VStack(alignment: .leading, spacing: 3) {
                Text(statusTitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 240)
            }
        case .failed(let message):
            Text("\(statusTitle) · \(message)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        default:
            Text(statusSummary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 8) {
            switch manager.state {
            case .notInstalled:
                Button(L.tr("Download", "Скачать")) { manager.download() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!ParakeetTranscriber.isAppleSilicon)
            case .partial:
                Button(L.tr("Retry", "Повторить")) { manager.download() }
                    .buttonStyle(.borderedProminent)
            case .installed:
                Button(L.tr("Verify", "Проверить")) { Task { await manager.validate() } }
                    .buttonStyle(.bordered)
            case .downloading:
                Button(L.tr("Cancel", "Отменить")) { manager.cancelDownload() }
                    .buttonStyle(.bordered)
            case .failed:
                Button(L.tr("Repair", "Исправить")) { manager.download(force: true) }
                    .buttonStyle(.borderedProminent)
            case .ready, .validating, .deleting:
                EmptyView()
            }

            if canDelete {
                Button(role: .destructive) { manager.deleteModel() } label: {
                    Image(systemName: "trash").foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.swPlainInteractive)
                .disabled(isBusy)
            }
        }
    }

    private var statusTitle: String {
        switch manager.state {
        case .notInstalled: return L.tr("Model not downloaded", "Модель не скачана")
        case .partial: return L.tr("Download incomplete", "Скачивание не завершено")
        case .installed: return L.tr("Model downloaded", "Модель скачана")
        case .validating: return L.tr("Checking model…", "Проверяю модель…")
        case .downloading(let progress, let stage):
            return "\(stageTitle(stage)) · \(Int(progress * 100))%"
        case .ready: return L.tr("Ready", "Готово")
        case .deleting: return L.tr("Deleting…", "Удаляю…")
        case .failed: return L.tr("Model needs repair", "Модель нужно исправить")
        }
    }

    private var statusSubtitle: String {
        switch manager.state {
        case .notInstalled: return L.tr("~460 MB · on-demand download", "~460 МБ · скачивание по команде")
        case .partial: return L.tr("Retry continues the saved download.", "Повторение продолжит сохранённую загрузку.")
        case .installed: return L.tr("Run a local check before first use.", "Проверьте модель локально перед первым запуском.")
        case .ready: return L.tr("Runs locally on Apple Silicon.", "Работает локально на Apple Silicon.")
        case .deleting: return L.tr("Removing the local model.", "Удаляю локальную модель.")
        case .validating: return L.tr("No network connection required.", "Интернет не требуется.")
        case .downloading, .failed: return ""
        }
    }

    private var statusSummary: String {
        if !ParakeetTranscriber.isAppleSilicon {
            return L.tr("Requires Apple Silicon", "Нужен Apple Silicon")
        }
        let subtitle = statusSubtitle
        return subtitle.isEmpty ? statusTitle : "\(statusTitle) · \(subtitle)"
    }

    private func stageTitle(_ stage: ParakeetDownloadStage) -> String {
        switch stage {
        case .listing: return L.tr("Preparing", "Подготовка")
        case .downloading: return L.tr("Downloading", "Скачивание")
        case .compiling: return L.tr("Compiling", "Компиляция")
        }
    }

    private var canDelete: Bool {
        switch manager.state {
        case .partial, .installed, .ready, .failed: return manager.isModelInstalled || manager.state == .partial
        case .notInstalled, .validating, .downloading, .deleting: return false
        }
    }

    private var isBusy: Bool {
        switch manager.state {
        case .validating, .downloading, .deleting: return true
        default: return false
        }
    }
}
