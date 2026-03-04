import Foundation
import AppKit

class GitHubUpdater {
    static let shared = GitHubUpdater()
    private let repo = "iddictive/Whisper-Free"
    private let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.0"
    private var isChecking = false

    func checkForUpdates(manual: Bool = false) {
        // In a real app, we'd check AppSettings here for auto-update flag
        guard !isChecking else { return }
        isChecking = true
        
        print("🔍 Checking for updates at https://api.github.com/repos/\(repo)/releases/latest")
        
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("WhisperFreeUpdater", forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            defer { self?.isChecking = false }
            guard let data = data, error == nil else { 
                print("❌ Update check network error: \(error?.localizedDescription ?? "unknown")")
                return 
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let tagName = json["tag_name"] as? String {
                    
                    let latestVersion = tagName.replacingOccurrences(of: "v", with: "")
                    print("📡 Latest version found: \(latestVersion) (current: \(self?.currentVersion ?? "unknown"))")
                    
                    if self?.compareVersions(current: self?.currentVersion ?? "", latest: latestVersion) == true {
                        let assets = json["assets"] as? [[String: Any]]
                        let dmgAsset = assets?.first(where: { ($0["name"] as? String)?.hasSuffix(".dmg") == true })
                        let downloadUrl = dmgAsset?["browser_download_url"] as? String
                        
                        DispatchQueue.main.async {
                            self?.showUpdateAlert(version: latestVersion, downloadUrl: downloadUrl)
                        }
                    } else if manual {
                        DispatchQueue.main.async {
                            let alert = NSAlert()
                            alert.messageText = "You're up to date!"
                            alert.informativeText = "WhisperFree \(self?.currentVersion ?? "") is the latest version."
                            alert.runModal()
                        }
                    }
                }
            } catch {
                print("❌ Update check JSON error: \(error)")
            }
        }.resume()
    }

    private func compareVersions(current: String, latest: String) -> Bool {
        return latest.compare(current, options: .numeric) == .orderedDescending
    }

    private func showUpdateAlert(version: String, downloadUrl: String?) {
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "A new version (\(version)) of WhisperFree is available. Would you like to download and install it now?"
        alert.addButton(withTitle: "Download & Install")
        alert.addButton(withTitle: "Later")
        
        if alert.runModal() == .alertFirstButtonReturn, let urlString = downloadUrl, let url = URL(string: urlString) {
            startAutomatedUpdate(url: url)
        }
    }

    private func startAutomatedUpdate(url: URL) {
        // Show a simple progress alert
        let progress = NSAlert()
        progress.messageText = "Downloading update..."
        let indicator = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 200, height: 20))
        indicator.isIndeterminate = true
        indicator.startAnimation(nil)
        progress.accessoryView = indicator
        
        // Use a background task to not block the modal if possible, 
        // though runModal is blocking. In a real app, we'd use a custom window.
        let downloadTask = URLSession.shared.downloadTask(with: url) { [weak self] localURL, _, error in
            DispatchQueue.main.async {
                if let localURL = localURL, error == nil {
                    // Create a temporary path that survives the alert closing
                    let tempPath = NSTemporaryDirectory() + "WhisperFreeUpdate.dmg"
                    try? FileManager.default.removeItem(atPath: tempPath)
                    try? FileManager.default.copyItem(at: localURL, to: URL(fileURLWithPath: tempPath))
                    
                    progress.window.close()
                    self?.performInstallation(dmgPath: tempPath)
                } else {
                    let fail = NSAlert()
                    fail.messageText = "Update Failed"
                    fail.informativeText = error?.localizedDescription ?? "Download failed."
                    fail.runModal()
                }
            }
        }
        
        downloadTask.resume()
        progress.runModal()
    }

    private func performInstallation(dmgPath: String) {
        let installAlert = NSAlert()
        installAlert.messageText = "Installing update..."
        let indicator = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 200, height: 20))
        indicator.isIndeterminate = true
        indicator.startAnimation(nil)
        installAlert.accessoryView = indicator
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let script = """
            mkdir -p /tmp/whisperfree_update
            hdiutil attach "\(dmgPath)" -mountpoint /tmp/whisperfree_update -nobrowse -quiet
            cp -R /tmp/whisperfree_update/WhisperFree.app /Applications/
            hdiutil detach /tmp/whisperfree_update -quiet
            """
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", script]
            try? process.run()
            process.waitUntilExit()
            
            DispatchQueue.main.async {
                installAlert.window.close()
                if process.terminationStatus == 0 {
                    self?.relaunch()
                } else {
                    let fail = NSAlert()
                    fail.messageText = "Installation failed"
                    fail.informativeText = "Could not copy the new version to /Applications."
                    fail.runModal()
                }
            }
        }
        installAlert.runModal()
    }

    private func relaunch() {
        let appPath = "/Applications/WhisperFree.app"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [appPath]
        try? process.run()
        NSApp.terminate(nil)
    }
}
