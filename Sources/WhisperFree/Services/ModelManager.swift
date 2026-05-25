import Foundation

final class ModelManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published var downloadedModels: Set<String> = []
    /// Per-model download state
    @Published var activeDownloads: [String: DownloadState] = [:]

    struct DownloadState {
        var progress: Double = 0
        var error: String?
        var isPreparing: Bool = false
        var startTime: Date?
        var bytesWritten: Int64 = 0
        var speed: Double = 0 // bytes per second
        var timeRemaining: TimeInterval?
    }

    private var tasks: [URLSessionDownloadTask: LocalModelSize] = [:]
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.isDiscretionary = false // not background-only
        config.sessionSendsLaunchEvents = false
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()

    override init() {
        super.init()
        refreshDownloadedModels()
    }

    func refreshDownloadedModels() {
        objectWillChange.send()
        var models = Set<String>()
        for size in LocalModelSize.allCases {
            if findModelPath(for: size) != nil {
                models.insert(size.rawValue)
            }
        }
        downloadedModels = models
    }

    /// Finds the actual path for a model file, checking local storage first, then system paths.
    func findModelPath(for size: LocalModelSize) -> URL? {
        // 1. Check App Storage (Sandboxed/Internal)
        let localPath = Storage.modelsDirectory.appendingPathComponent(size.fileName)
        if FileManager.default.fileExists(atPath: localPath.path) {
            return localPath
        }

        // 2. Check Legacy / System paths
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let systemPaths = [
            "/opt/homebrew/share/whisper-cpp/models/\(size.fileName)",
            "/opt/homebrew/share/whisper.cpp/models/\(size.fileName)",
            "/opt/homebrew/share/whisper-cpp/\(size.fileName)",
            "/opt/homebrew/share/whisper.cpp/\(size.fileName)",
            "/usr/local/share/whisper-cpp/models/\(size.fileName)",
            "/usr/local/share/whisper.cpp/models/\(size.fileName)",
            homeDir.appendingPathComponent("Library/Containers/com.whisperfree.app/Data/Library/Application Support/WhisperKiller/Models/\(size.fileName)").path,
            homeDir.appendingPathComponent("Library/Containers/com.whisperfree.app/Data/Library/Application Support/WhisperFree/Models/\(size.fileName)").path,
            homeDir.appendingPathComponent("Library/Application Support/WhisperFree/Models/\(size.fileName)").path,
            homeDir.appendingPathComponent("Library/Application Support/superwhisper/Models/\(size.fileName)").path,
            homeDir.appendingPathComponent(".cache/whisper/\(size.fileName)").path
        ]

        for path in systemPaths {
            // Use resolvingSymlinksInPath to handle Homebrew alias/symlink messes
            let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        return nil
    }

    func isModelDownloaded(_ size: LocalModelSize) -> Bool {
        downloadedModels.contains(size.rawValue)
    }

    func isDownloading(_ size: LocalModelSize) -> Bool {
        activeDownloads[size.rawValue] != nil
    }

    func progress(for size: LocalModelSize) -> Double {
        activeDownloads[size.rawValue]?.progress ?? 0
    }

    func error(for size: LocalModelSize) -> String? {
        activeDownloads[size.rawValue]?.error
    }

    var isAnyDownloading: Bool {
        !activeDownloads.isEmpty
    }

    func downloadModel(_ size: LocalModelSize) {
        guard activeDownloads[size.rawValue] == nil else { return }

        // Ensure UI knows we are starting immediately
        objectWillChange.send()
        activeDownloads[size.rawValue] = DownloadState(isPreparing: true)

        let task = session.downloadTask(with: size.downloadURL)
        tasks[task] = size
        task.resume()
    }

    func cancelDownload(_ size: LocalModelSize) {
        for (task, model) in tasks where model == size {
            task.cancel()
            tasks.removeValue(forKey: task)
        }
        activeDownloads.removeValue(forKey: size.rawValue)
    }

    func deleteModel(_ size: LocalModelSize) {
        let path = Storage.modelsDirectory.appendingPathComponent(size.fileName)
        try? FileManager.default.removeItem(at: path)
        refreshDownloadedModels()
    }

    func modelFileSize(_ size: LocalModelSize) -> String? {
        let path = Storage.modelsDirectory.appendingPathComponent(size.fileName)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path.path),
              let fileSize = attrs[.size] as? UInt64
        else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(fileSize))
    }

    func isQwenModelDownloaded(_ model: QwenASRModel) -> Bool {
        let hubDirectory = Storage.qwenASRCacheDirectory.appendingPathComponent("hub", isDirectory: true)
        let modelDirectory = hubDirectory.appendingPathComponent("models--\(model.cacheDirectoryName)", isDirectory: true)
        let snapshotsDirectory = modelDirectory.appendingPathComponent("snapshots", isDirectory: true)
        let blobsDirectory = modelDirectory.appendingPathComponent("blobs", isDirectory: true)

        if let blobFiles = try? FileManager.default.contentsOfDirectory(
            at: blobsDirectory,
            includingPropertiesForKeys: nil
        ), blobFiles.contains(where: { $0.lastPathComponent.hasSuffix(".incomplete") }) {
            return false
        }

        guard FileManager.default.fileExists(atPath: snapshotsDirectory.path),
              let snapshots = try? FileManager.default.contentsOfDirectory(
                at: snapshotsDirectory,
                includingPropertiesForKeys: nil
              )
        else { return false }

        return snapshots.contains { snapshot in
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: snapshot,
                includingPropertiesForKeys: nil
            ) else { return false }

            let hasConfig = files.contains { $0.lastPathComponent == "config.json" }
            let hasWeights = files.contains { file in
                let name = file.lastPathComponent.lowercased()
                return name.hasSuffix(".safetensors")
                    || name.hasSuffix(".bin")
                    || name.hasSuffix(".npz")
                    || name.contains("model")
            }
            return hasConfig && hasWeights
        }
    }

    func deleteQwenModel(_ model: QwenASRModel) {
        let hubDirectory = Storage.qwenASRCacheDirectory.appendingPathComponent("hub", isDirectory: true)
        let modelDirectory = hubDirectory.appendingPathComponent("models--\(model.cacheDirectoryName)", isDirectory: true)
        try? FileManager.default.removeItem(at: modelDirectory)
        refreshDownloadedModels()
    }

    func hasPartialQwenModelDownload(_ model: QwenASRModel) -> Bool {
        let hubDirectory = Storage.qwenASRCacheDirectory.appendingPathComponent("hub", isDirectory: true)
        let blobsDirectory = hubDirectory
            .appendingPathComponent("models--\(model.cacheDirectoryName)", isDirectory: true)
            .appendingPathComponent("blobs", isDirectory: true)
        guard let blobFiles = try? FileManager.default.contentsOfDirectory(
            at: blobsDirectory,
            includingPropertiesForKeys: nil
        ) else { return false }
        return blobFiles.contains { $0.lastPathComponent.hasSuffix(".incomplete") }
    }

    func qwenModelFileSize(_ model: QwenASRModel) -> String? {
        let hubDirectory = Storage.qwenASRCacheDirectory.appendingPathComponent("hub", isDirectory: true)
        let modelDirectory = hubDirectory.appendingPathComponent("models--\(model.cacheDirectoryName)", isDirectory: true)
        guard let size = directorySize(at: modelDirectory), size > 0 else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }

    private func directorySize(at url: URL) -> UInt64? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: keys),
                  values.isRegularFile == true
            else { continue }
            total += UInt64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let size = tasks[downloadTask] else { return }
        
        var state = activeDownloads[size.rawValue] ?? DownloadState()
        
        if state.startTime == nil {
            state.startTime = Date()
            state.isPreparing = false
        }
        
        state.bytesWritten = totalBytesWritten
        
        if let startTime = state.startTime {
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed > 0 {
                state.speed = Double(totalBytesWritten) / elapsed
                
                if totalBytesExpectedToWrite > 0 {
                    let remainingBytes = Double(totalBytesExpectedToWrite - totalBytesWritten)
                    state.timeRemaining = remainingBytes / state.speed
                    state.progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
                }
            }
        }
        
        activeDownloads[size.rawValue] = state
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let size = tasks[downloadTask] else { return }
        let destination = Storage.modelsDirectory.appendingPathComponent(size.fileName)

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            refreshDownloadedModels()
        } catch {
            activeDownloads[size.rawValue]?.error = error.localizedDescription
        }

        tasks.removeValue(forKey: downloadTask)
        activeDownloads.removeValue(forKey: size.rawValue)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let dlTask = task as? URLSessionDownloadTask,
              let size = tasks[dlTask] else { return }
        if let error = error as? NSError, error.code != NSURLErrorCancelled {
            activeDownloads[size.rawValue]?.error = error.localizedDescription
        }
        tasks.removeValue(forKey: dlTask)
        // Keep activeDownloads entry for error display, remove after delay
        if activeDownloads[size.rawValue]?.error != nil {
            let key = size.rawValue
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.activeDownloads.removeValue(forKey: key)
            }
        } else {
            activeDownloads.removeValue(forKey: size.rawValue)
        }
    }
}
