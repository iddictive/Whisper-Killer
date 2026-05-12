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
    
    @Published var isInstallingOllama = false
    @Published var ollamaProgress: Double = 0.0
    @Published var ollamaStatus: String = ""
    @Published var isInstallingHomebrew = false
    @Published var homebrewStatus: String = ""
    @Published var isInstallingWhisperCpp = false
    @Published var whisperCppStatus: String = ""
    @Published var isInstallingGigaAM = false
    @Published var gigaAMStatus: String = ""
    
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

    nonisolated private static func runBrewInstallWhisperCpp() -> Result<Void, DependencyError> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")

        let brewPath = findHomebrewPath()
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
                    commandDescription: "brew install whisper-cpp",
                    detectHomebrewPermissionFailure: true
                )
                return .failure(.installationFailed(message))
            }

            return .success(())
        } catch {
            return .failure(.installationFailed(error.localizedDescription))
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
        detectHomebrewPermissionFailure: Bool
    ) -> String {
        guard let output, !output.isEmpty else {
            return "\(commandDescription) exited with code \(status)."
        }

        if detectHomebrewPermissionFailure,
           let message = homebrewPermissionFailureMessage(from: output) {
            return message
        }

        let maxLength = 600
        if output.count <= maxLength {
            return output
        }

        return String(output.suffix(maxLength))
    }

    nonisolated private static func homebrewPermissionFailureMessage(from output: String) -> String? {
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

        let prefix: String
        if output.contains("/opt/homebrew") {
            prefix = "/opt/homebrew"
        } else if output.contains("/usr/local") {
            prefix = "/usr/local"
        } else {
            prefix = "$(brew --prefix)"
        }

        return L.tr(
            "Homebrew permissions need repair. Run in Terminal: sudo chown -R $(whoami) \(prefix) && chmod -R u+w \(prefix)",
            "Нужно исправить права Homebrew. В Terminal: sudo chown -R $(whoami) \(prefix) && chmod -R u+w \(prefix)"
        )
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
