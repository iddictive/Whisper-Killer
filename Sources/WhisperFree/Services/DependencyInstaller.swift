import Foundation
import AppKit

enum DependencyError: Error, LocalizedError {
    case downloadFailed
    case extractionFailed
    case installationFailed(String)
    case scriptExecutionFailed
    
    var errorDescription: String? {
        switch self {
        case .downloadFailed: return "Failed to download the installation package."
        case .extractionFailed: return "Failed to extract the downloaded files."
        case .installationFailed(let reason): return "Installation failed: \(reason)"
        case .scriptExecutionFailed: return "Failed to execute the required admin script."
        }
    }
}

@MainActor
final class DependencyInstaller: ObservableObject {
    static let shared = DependencyInstaller()
    
    @Published var isInstallingOllama = false
    @Published var ollamaProgress: Double = 0.0
    @Published var ollamaStatus: String = ""
    
    private init() {}
    
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
