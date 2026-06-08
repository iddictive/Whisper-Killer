import Foundation
import AppKit
import Combine

class GitHubUpdater: ObservableObject {
    static let shared = GitHubUpdater()
    private let repo = "iddictive/Whisper-Killer"
    let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "3.0"

    @Published var isChecking = false
    @Published var updateAvailable = false
    @Published var latestVersion: String?
    @Published var downloadUrl: String?
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var error: String?

    private var downloadTask: URLSessionDownloadTask?
    private var observation: NSKeyValueObservation?

    func checkForUpdates(manual: Bool = false) {
        guard !isChecking else { return }

        let updateSettings = Storage.shared.loadSettings()
        if !manual && !updateSettings.automaticallyChecksForUpdates { return }

        isChecking = true
        error = nil

        print("🔍 Checking for updates at https://api.github.com/repos/\(repo)/releases/latest")

        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("WhisperKillerUpdater", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isChecking = false
                guard let data = data, error == nil else {
                    self?.error = error?.localizedDescription ?? "Network error"
                    return
                }

                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let tagName = json["tag_name"] as? String {

                        let latest = tagName.replacingOccurrences(of: "v", with: "")
                        self?.latestVersion = latest
                        self?.updateAvailable = false
                        self?.downloadUrl = nil

                        let automaticallyDownloadsUpdates = Storage.shared.loadSettings().automaticallyDownloadsUpdates

                        if self?.compareVersions(current: self?.currentVersion ?? "", latest: latest) == true {
                            self?.updateAvailable = true
                            let assets = json["assets"] as? [[String: Any]]
                            let dmgAsset = assets?.first(where: { ($0["name"] as? String)?.hasSuffix(".dmg") == true })
                            self?.downloadUrl = dmgAsset?["browser_download_url"] as? String

                            if manual {
                                self?.showUpdateAlert(version: latest, downloadUrl: self?.downloadUrl)
                            } else if automaticallyDownloadsUpdates {
                                self?.startDownload()
                            }
                        } else if manual {
                            let alert = NSAlert()
                            alert.messageText = "You're up to date!"
                            alert.informativeText = "WhisperKiller \(self?.currentVersion ?? "") is the latest version."
                            alert.runModal()
                        }
                    }
                } catch {
                    self?.error = "JSON error"
                }
            }
        }.resume()
    }

    private func compareVersions(current: String, latest: String) -> Bool {
        return latest.compare(current, options: .numeric) == .orderedDescending
    }

    private func showUpdateAlert(version: String, downloadUrl: String?) {
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "A new version (\(version)) of WhisperKiller is available. Would you like to download and install it now?"
        alert.addButton(withTitle: "Download & Install")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            startDownload()
        }
    }

    func startDownload() {
        guard let urlString = downloadUrl, let url = URL(string: urlString), !isDownloading else { return }

        isDownloading = true
        downloadProgress = 0
        error = nil

        downloadTask = URLSession.shared.downloadTask(with: url) { [weak self] localURL, _, error in
            DispatchQueue.main.async {
                self?.isDownloading = false
                self?.observation = nil

                if let localURL = localURL, error == nil {
                    let tempPath = NSTemporaryDirectory() + "WhisperKillerUpdate.dmg"
                    try? FileManager.default.removeItem(atPath: tempPath)
                    try? FileManager.default.copyItem(at: localURL, to: URL(fileURLWithPath: tempPath))
                    self?.performInstallation(dmgPath: tempPath)
                } else {
                    self?.error = error?.localizedDescription ?? "Download failed"
                }
            }
        }

        // Track progress
        observation = downloadTask?.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            DispatchQueue.main.async {
                self?.downloadProgress = progress.fractionCompleted
            }
        }

        downloadTask?.resume()
    }

    private func performInstallation(dmgPath: String) {
        // Show install prompt if it was a background download
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Installation Ready"
            alert.informativeText = "The update has been downloaded. WhisperKiller will close to install the new version."
            alert.addButton(withTitle: "Install & Relaunch")
            alert.addButton(withTitle: "Later")

            if alert.runModal() == .alertFirstButtonReturn {
                self.runInstallScript(dmgPath: dmgPath)
            }
        }
    }

    private func runInstallScript(dmgPath: String) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let appPath = "/Applications/WhisperKiller.app"
        let mountPath = "/tmp/whisperfree_update"
        let stagedAppPath = "/tmp/WhisperKiller.updated.app"
        let backupAppPath = "/tmp/WhisperKiller.previous.app"
        let logPath = "/tmp/WhisperKillerUpdate.log"
        let expectedVersion = latestVersion ?? ""
        let script = """
        set -eu
        logPath="\(logPath)"
        appPath="\(appPath)"
        mountPath="\(mountPath)"
        stagedAppPath="\(stagedAppPath)"
        backupAppPath="\(backupAppPath)"
        dmgPath="\(dmgPath)"
        expectedVersion="\(expectedVersion)"
        executableName="WhisperKiller"
        needsRollback=0

        exec >> "$logPath" 2>&1

        log() {
            printf '%s %s\\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"
        }

        rollback() {
            log "Rolling back to previous app"
            pkill -x "$executableName" 2>/dev/null || true
            rm -rf "$appPath"
            if [ -d "$backupAppPath" ]; then
                ditto "$backupAppPath" "$appPath"
                open "$appPath"
                log "Rollback complete"
            else
                log "Rollback skipped: backup missing"
            fi
        }

        finish() {
            status=$?
            if [ "$status" -ne 0 ] && [ "$needsRollback" = "1" ]; then
                rollback
            fi
            hdiutil detach "$mountPath" -quiet 2>/dev/null || true
            rm -rf "$mountPath" "$stagedAppPath"
            exit "$status"
        }
        trap finish EXIT

        log "Starting update install"
        while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done

        rm -rf "$mountPath" "$stagedAppPath"
        mkdir -p "$mountPath"
        hdiutil attach "$dmgPath" -mountpoint "$mountPath" -nobrowse -quiet

        sourceAppPath="$mountPath/WhisperKiller.app"
        if [ ! -x "$sourceAppPath/Contents/MacOS/$executableName" ]; then
            log "Staged app is missing executable"
            exit 1
        fi

        ditto "$sourceAppPath" "$stagedAppPath"
        xattr -rc "$stagedAppPath" || true
        codesign --verify --deep --strict "$stagedAppPath"

        stagedVersion="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$stagedAppPath/Contents/Info.plist" 2>/dev/null || true)"
        if [ -z "$stagedVersion" ]; then
            log "Staged app version is missing"
            exit 1
        fi
        if [ -n "$expectedVersion" ] && [ "$stagedVersion" != "$expectedVersion" ]; then
            log "Staged app version $stagedVersion does not match expected $expectedVersion"
            exit 1
        fi

        rm -rf "$backupAppPath"
        if [ -d "$appPath" ]; then
            ditto "$appPath" "$backupAppPath"
            needsRollback=1
        fi

        rm -rf "$appPath"
        ditto "$stagedAppPath" "$appPath"
        log "Installed version $stagedVersion"

        open "$appPath"
        smokePassed=0
        for _ in {1..30}; do
            sleep 0.5
            if pgrep -x "$executableName" >/dev/null; then
                sleep 3
                if pgrep -x "$executableName" >/dev/null; then
                    smokePassed=1
                    break
                fi
            fi
        done

        if [ "$smokePassed" != "1" ]; then
            log "Smoke launch failed"
            exit 1
        fi

        needsRollback=0
        rm -rf "$backupAppPath"
        log "Update install succeeded"
        """

        do {
            try launchDetachedShellScript(script)
            NSApp.terminate(nil)
        } catch {
            print("❌ Installation error: \(error)")
        }
    }

    private func launchDetachedShellScript(_ script: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script]
        try process.run()
    }
}
