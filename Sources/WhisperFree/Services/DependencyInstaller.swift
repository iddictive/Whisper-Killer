import Foundation
import AppKit

enum DependencyError: Error, LocalizedError {
    case downloadFailed
    case extractionFailed
    case installationFailed(String)
    case scriptExecutionFailed
    
    var errorDescription: String? {
        switch self {
        case .downloadFailed:
            return L.tr("Failed to download the installation package.", "Не удалось скачать установочный пакет.")
        case .extractionFailed:
            return L.tr("Failed to extract the downloaded files.", "Не удалось распаковать скачанные файлы.")
        case .installationFailed(let reason):
            return L.tr("Installation failed: \(reason)", "Не удалось установить: \(reason)")
        case .scriptExecutionFailed:
            return L.tr("Failed to execute the required admin script.", "Не удалось запустить системный скрипт установки.")
        }
    }
}

@MainActor
final class DependencyInstaller: ObservableObject {
    static let shared = DependencyInstaller()

    private struct CommandFailure: Error {
        let status: Int32
        let output: String?
    }

    private struct HomebrewPermissionFailure {
        let prefix: String
        let message: String
    }
    
    @Published var isInstallingOllama = false
    @Published var ollamaProgress: Double = 0.0
    @Published var ollamaStatus: String = ""
    @Published var isInstallingHomebrew = false
    @Published var homebrewStatus: String = ""
    @Published var isInstallingWhisperCpp = false
    @Published var whisperCppStatus: String = ""
    @Published var isInstallingGigaAM = false
    @Published var gigaAMStatus: String = ""
    @Published var isInstallingQwenASR = false
    @Published var qwenASRStatus: String = ""
    
    private init() {}

    // MARK: - whisper.cpp Installation

    var isHomebrewInstalled: Bool {
        Self.findHomebrewPath() != nil
    }

    var isWhisperCppInstalled: Bool {
        LocalWhisper.findWhisperBinary() != nil
    }

    var isGigaAMEnvironmentInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: GigaAMTranscriber.virtualEnvironmentPythonPath)
    }

    var isQwenASRRuntimeInstalled: Bool {
        QwenASRTranscriber.isRuntimeInstalled
    }

    func installHomebrew() {
        guard !isInstallingHomebrew else { return }

        isInstallingHomebrew = true
        homebrewStatus = "Opening Homebrew installer in Terminal..."

        Task(priority: .userInitiated) {
            let result = await Task.detached(priority: .userInitiated) {
                Self.openHomebrewInstallerInTerminal()
            }.value

            switch result {
            case .success:
                self.homebrewStatus = "Finish Homebrew setup in Terminal, then return here."
            case .failure(let error):
                self.isInstallingHomebrew = false
                self.homebrewStatus = error.localizedDescription
            }
        }
    }

    func refreshHomebrewStatus() {
        if isHomebrewInstalled {
            isInstallingHomebrew = false
            homebrewStatus = "Homebrew detected."
        } else if isInstallingHomebrew {
            homebrewStatus = "Finish Homebrew setup in Terminal, then return here."
        }
    }

    func installWhisperCpp(onComplete: (() -> Void)? = nil) {
        guard !isInstallingWhisperCpp else { return }

        guard isHomebrewInstalled else {
            whisperCppStatus = "Homebrew is required first."
            return
        }

        isInstallingWhisperCpp = true
        whisperCppStatus = "Installing whisper-cpp..."

        Task(priority: .userInitiated) {
            let result = await Task.detached(priority: .userInitiated) {
                Self.runBrewInstallWhisperCpp()
            }.value

            self.isInstallingWhisperCpp = false

            switch result {
            case .success:
                self.whisperCppStatus = "whisper-cpp installed."
            case .failure(let error):
                self.whisperCppStatus = error.localizedDescription
            }

            onComplete?()
        }
    }

    func installGigaAMDependencies() {
        guard !isInstallingGigaAM else { return }

        guard let python = GigaAMTranscriber.findBasePythonBinary() else {
            gigaAMStatus = "Python 3.10-3.13 is required."
            return
        }

        isInstallingGigaAM = true
        gigaAMStatus = "Installing GigaAM runtime..."

        Task(priority: .userInitiated) {
            let result = await Task.detached(priority: .userInitiated) {
                Self.runGigaAMInstall(basePythonPath: python)
            }.value

            self.isInstallingGigaAM = false

            switch result {
            case .success:
                self.gigaAMStatus = "GigaAM runtime installed."
            case .failure(let error):
                self.gigaAMStatus = error.localizedDescription
            }
        }
    }

    func refreshGigaAMStatus() {
        if isGigaAMEnvironmentInstalled {
            gigaAMStatus = "GigaAM runtime detected."
        } else if GigaAMTranscriber.findBasePythonBinary() == nil {
            gigaAMStatus = "Python 3.10-3.13 is required."
        } else if isInstallingGigaAM {
            gigaAMStatus = "Installing GigaAM runtime..."
        } else {
            gigaAMStatus = ""
        }
    }

    func installQwenASRRuntime() {
        guard !isInstallingQwenASR else { return }

        guard QwenASRTranscriber.isAppleSilicon else {
            qwenASRStatus = "Qwen3-ASR MLX requires Apple Silicon."
            return
        }

        guard let python = QwenASRTranscriber.findBasePythonBinary() else {
            qwenASRStatus = "Python 3.10+ runtime not found. Bundle Python with the app for fully self-contained installs."
            return
        }

        isInstallingQwenASR = true
        qwenASRStatus = "Installing Qwen3-ASR MLX runtime..."

        Task(priority: .userInitiated) {
            do {
                try await QwenASRTranscriber.installRuntime(basePythonPath: python)
                self.qwenASRStatus = "Qwen3-ASR runtime installed."
            } catch {
                self.qwenASRStatus = error.localizedDescription
            }
            self.isInstallingQwenASR = false
        }
    }

    func refreshQwenASRStatus() {
        if QwenASRTranscriber.isRuntimeInstalled {
            qwenASRStatus = "Qwen3-ASR runtime detected."
        } else if !QwenASRTranscriber.isAppleSilicon {
            qwenASRStatus = "Qwen3-ASR MLX requires Apple Silicon."
        } else if QwenASRTranscriber.findBasePythonBinary() == nil {
            qwenASRStatus = "Python 3.10+ runtime not found."
        } else if isInstallingQwenASR {
            qwenASRStatus = "Installing Qwen3-ASR MLX runtime..."
        } else {
            qwenASRStatus = ""
        }
    }

    nonisolated private static func runBrewInstallWhisperCpp() -> Result<Void, DependencyError> {
        let brewPath = findHomebrewPath()
        let firstAttempt = runBrewInstallWhisperCppOnce(brewPath: brewPath)

        switch firstAttempt {
        case .success:
            return .success(())
        case .failure(let failure):
            guard let permissionFailure = homebrewPermissionFailure(from: failure.output, brewPath: brewPath) else {
                return .failure(.installationFailed(
                    installFailureMessage(
                        from: failure.output,
                        status: failure.status,
                        commandDescription: "brew install whisper-cpp",
                        detectHomebrewPermissionFailure: true,
                        brewPath: brewPath
                    )
                ))
            }

            switch repairHomebrewPermissions(prefix: permissionFailure.prefix) {
            case .success:
                let retryAttempt = runBrewInstallWhisperCppOnce(brewPath: brewPath)
                switch retryAttempt {
                case .success:
                    return .success(())
                case .failure(let retryFailure):
                    return .failure(.installationFailed(
                        installFailureMessage(
                            from: retryFailure.output,
                            status: retryFailure.status,
                            commandDescription: "brew install whisper-cpp after Homebrew permission repair",
                            detectHomebrewPermissionFailure: true,
                            brewPath: brewPath
                        )
                    ))
                }
            case .failure(let error):
                return .failure(error)
            }
        }
    }

    nonisolated private static func runBrewInstallWhisperCppOnce(brewPath: String?) -> Result<Void, CommandFailure> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")

        process.arguments = [
            "-lc",
            """
            "\(brewPath ?? "brew")" install whisper-cpp
            """
        ]

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisper_cpp_install_\(UUID().uuidString).log")
        _ = FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        guard let outputHandle = try? FileHandle(forWritingTo: outputURL) else {
            return .failure(CommandFailure(status: -1, output: "Could not create install log."))
        }
        defer {
            try? outputHandle.close()
            try? FileManager.default.removeItem(at: outputURL)
        }

        process.standardOutput = outputHandle
        process.standardError = outputHandle

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let output = (try? String(contentsOf: outputURL, encoding: .utf8))?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return .failure(CommandFailure(status: process.terminationStatus, output: output))
            }

            return .success(())
        } catch {
            return .failure(CommandFailure(status: -1, output: error.localizedDescription))
        }
    }

    nonisolated private static func runGigaAMInstall(basePythonPath: String) -> Result<Void, DependencyError> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")

        let venvPythonPath = GigaAMTranscriber.virtualEnvironmentPythonPath
        let venvDirectory = URL(fileURLWithPath: venvPythonPath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
        let installRoot = URL(fileURLWithPath: venvDirectory)
            .deletingLastPathComponent()
            .path

        process.arguments = [
            "-lc",
            """
            mkdir -p "\(installRoot)"
            "\(basePythonPath)" -m venv "\(venvDirectory)"
            "\(venvPythonPath)" -m pip install --trusted-host pypi.org --trusted-host files.pythonhosted.org torch torchaudio transformers 'huggingface-hub<1.0' pyannote-audio torchcodec hydra-core omegaconf sentencepiece
            """
        ]

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("gigaam_install_\(UUID().uuidString).log")
        _ = FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        guard let outputHandle = try? FileHandle(forWritingTo: outputURL) else {
            return .failure(.installationFailed("Could not create install log."))
        }
        defer {
            try? outputHandle.close()
            try? FileManager.default.removeItem(at: outputURL)
        }

        process.standardOutput = outputHandle
        process.standardError = outputHandle

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let output = (try? String(contentsOf: outputURL, encoding: .utf8))?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let message = installFailureMessage(
                    from: output,
                    status: process.terminationStatus,
                    commandDescription: "GigaAM dependency install",
                    detectHomebrewPermissionFailure: false
                )
                return .failure(.installationFailed(message))
            }

            return .success(())
        } catch {
            return .failure(.installationFailed(error.localizedDescription))
        }
    }

    nonisolated private static func installFailureMessage(
        from output: String?,
        status: Int32,
        commandDescription: String,
        detectHomebrewPermissionFailure: Bool,
        brewPath: String? = nil
    ) -> String {
        guard let output, !output.isEmpty else {
            return "\(commandDescription) exited with code \(status)."
        }

        if detectHomebrewPermissionFailure,
           let permissionFailure = homebrewPermissionFailure(from: output, brewPath: brewPath) {
            return permissionFailure.message
        }

        let maxLength = 600
        if output.count <= maxLength {
            return output
        }

        return String(output.suffix(maxLength))
    }

    nonisolated private static func homebrewPermissionFailure(from output: String?, brewPath: String?) -> HomebrewPermissionFailure? {
        guard let output, !output.isEmpty else { return nil }

        let normalized = output.lowercased()
        let isHomebrewPermissionFailure =
            normalized.contains("homebrew")
            && (
                normalized.contains("not writable")
                || normalized.contains("you should change the ownership")
                || normalized.contains("permission denied")
                || normalized.contains("operation not permitted")
            )

        guard isHomebrewPermissionFailure else { return nil }

        guard let prefix = homebrewPrefix(from: output, brewPath: brewPath) else {
            return nil
        }

        let message = L.tr(
            "Homebrew permissions need repair. Run in Terminal: sudo chown -R $(whoami) \(prefix) && chmod -R u+w \(prefix)",
            "Нужно исправить права Homebrew. В Terminal: sudo chown -R $(whoami) \(prefix) && chmod -R u+w \(prefix)"
        )

        return HomebrewPermissionFailure(prefix: prefix, message: message)
    }

    nonisolated private static func homebrewPrefix(from output: String, brewPath: String?) -> String? {
        if output.contains("/opt/homebrew") {
            return "/opt/homebrew"
        }

        if output.contains("/usr/local") {
            return "/usr/local"
        }

        guard let brewPath else { return nil }

        return URL(fileURLWithPath: brewPath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
    }

    nonisolated private static func repairHomebrewPermissions(prefix: String) -> Result<Void, DependencyError> {
        let userName = NSUserName()
        guard !userName.isEmpty, userName != "root" else {
            return .failure(.installationFailed(L.tr(
                "Could not determine the current macOS user for Homebrew repair.",
                "Не удалось определить текущего пользователя macOS для ремонта Homebrew."
            )))
        }

        let repairCommand = """
        set -e
        /usr/sbin/chown -R \(shellQuoted(userName)) \(shellQuoted(prefix))
        /bin/chmod -R u+w \(shellQuoted(prefix))
        """
        let script = """
        do shell script "\(appleScriptEscaped(repairCommand))" with administrator privileges
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return .failure(.installationFailed(homebrewRepairFailureMessage(output: output)))
            }

            return .success(())
        } catch {
            return .failure(.installationFailed(error.localizedDescription))
        }
    }

    nonisolated private static func homebrewRepairFailureMessage(output: String?) -> String {
        let normalized = output?.lowercased() ?? ""
        if normalized.contains("user canceled") || normalized.contains("(-128)") {
            return L.tr(
                "Homebrew repair was cancelled. Run the repair command manually, then install again.",
                "Ремонт Homebrew отменён. Запустите команду исправления прав вручную и повторите установку."
            )
        }

        guard let output, !output.isEmpty else {
            return L.tr(
                "Homebrew repair failed. Run the repair command manually, then install again.",
                "Не удалось исправить права Homebrew. Запустите команду вручную и повторите установку."
            )
        }

        return output
    }

    nonisolated private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    nonisolated static func findHomebrewPath() -> String? {
        let possiblePaths = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew"
        ]

        for path in possiblePaths where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["brew"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let path, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        return nil
    }

    nonisolated private static func openHomebrewInstallerInTerminal() -> Result<Void, DependencyError> {
        let command = #"""
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        echo
        echo "Homebrew setup finished. Return to WhisperKiller."
        """#
        let script = """
        tell application "Terminal"
            activate
            do script "\(appleScriptEscaped(command))"
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                return .failure(.scriptExecutionFailed)
            }

            return .success(())
        } catch {
            return .failure(.installationFailed(error.localizedDescription))
        }
    }

    nonisolated private static func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "; ")
    }
    
    // MARK: - Ollama Installation
    
    /// Downloads and installs Ollama to /Applications
    func installOllama() {
        guard !isInstallingOllama else { return }
        
        isInstallingOllama = true
        ollamaProgress = 0.0
        ollamaStatus = "Downloading Ollama..."
        
        Task(priority: .userInitiated) {
            do {
                let downloadURL = URL(string: "https://ollama.com/download/Ollama-darwin.zip")!
                let tempDir = FileManager.default.temporaryDirectory
                let zipDest = tempDir.appendingPathComponent("Ollama-darwin.zip")
                
                // Cleanup old zip
                try? FileManager.default.removeItem(at: zipDest)
                
                // Download with retry logic (up to 3 attempts)
                var downloadSuccess = false
                var attempts = 0
                let maxAttempts = 3
                
                while !downloadSuccess && attempts < maxAttempts {
                    attempts += 1
                    do {
                        let (tempURL, response) = try await URLSession.shared.download(from: downloadURL)
                        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                            if attempts >= maxAttempts { throw DependencyError.downloadFailed }
                            continue
                        }
                        try FileManager.default.moveItem(at: tempURL, to: zipDest)
                        downloadSuccess = true
                    } catch {
                        if attempts >= maxAttempts { throw error }
                        // Small delay before retry
                        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                        await MainActor.run {
                            self.ollamaStatus = "Retrying download (attempt \(attempts+1)/\(maxAttempts))..."
                        }
                    }
                }
                
                guard downloadSuccess else { throw DependencyError.downloadFailed }
                
                await MainActor.run {
                    self.ollamaProgress = 0.5
                    self.ollamaStatus = "Extracting Ollama..."
                }
                
                // Run extraction and installation in a background queue to not block the UI
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let extractProcess = Process()
                        extractProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                        extractProcess.arguments = ["-o", zipDest.path, "-d", tempDir.path]
                        try extractProcess.run()
                        extractProcess.waitUntilExit()
                        
                        guard extractProcess.terminationStatus == 0 else {
                            throw DependencyError.extractionFailed
                        }
                        
                        let extractedApp = tempDir.appendingPathComponent("Ollama.app")
                        let finalDest = URL(fileURLWithPath: "/Applications/Ollama.app")
                        
                        DispatchQueue.main.async {
                            self.ollamaProgress = 0.8
                            self.ollamaStatus = "Installing..."
                        }
                        
                        if FileManager.default.fileExists(atPath: finalDest.path) {
                            try? FileManager.default.removeItem(at: finalDest)
                        }
                        
                        try FileManager.default.moveItem(at: extractedApp, to: finalDest)
                        
                        DispatchQueue.main.async {
                            self.ollamaProgress = 1.0
                            self.ollamaStatus = "Launching Ollama..."
                            
                            // Launch
                            NSWorkspace.shared.openApplication(at: finalDest, configuration: NSWorkspace.OpenConfiguration()) { _, _ in 
                                DispatchQueue.main.async {
                                    self.isInstallingOllama = false
                                    self.ollamaStatus = "Installed Successfully"
                                }
                            }
                        }
                        
                        try? FileManager.default.removeItem(at: zipDest)
                        
                    } catch {
                        DispatchQueue.main.async {
                            self.isInstallingOllama = false
                            self.ollamaStatus = error.localizedDescription
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.isInstallingOllama = false
                    self.ollamaStatus = error.localizedDescription
                }
            }
        }
    }
}
