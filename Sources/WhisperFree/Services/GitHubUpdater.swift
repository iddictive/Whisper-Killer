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
                            _ = self?.runUpdaterAlert(
                                messageText: L.tr("You're up to date!", "Обновлений нет"),
                                informativeText: L.tr(
                                    "WhisperKiller \(self?.currentVersion ?? "") is the latest version.",
                                    "Установлена последняя версия WhisperKiller \(self?.currentVersion ?? "")."
                                ),
                                primaryButtonTitle: L.tr("OK", "ОК")
                            )
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
        let response = runUpdaterAlert(
            messageText: L.tr("Update Available", "Доступно обновление"),
            informativeText: L.tr(
                "A new version (\(version)) of WhisperKiller is available. Would you like to download and install it now?",
                "Доступна новая версия WhisperKiller \(version). Скачать и установить сейчас?"
            ),
            primaryButtonTitle: L.tr("Download & Install", "Скачать и установить"),
            secondaryButtonTitle: L.tr("Later", "Позже")
        )

        if response == .alertFirstButtonReturn {
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
            let response = self.runUpdaterAlert(
                messageText: L.tr("Installation Ready", "Готово к установке"),
                informativeText: L.tr(
                    "The update has been downloaded. WhisperKiller will close to install the new version.",
                    "Обновление загружено. WhisperKiller закроется, установит новую версию и запустится снова."
                ),
                primaryButtonTitle: L.tr("Install & Relaunch", "Установить и перезапустить"),
                secondaryButtonTitle: L.tr("Later", "Позже")
            )

            if response == .alertFirstButtonReturn {
                self.runInstallScript(dmgPath: dmgPath)
            }
        }
    }

    @discardableResult
    private func runUpdaterAlert(
        messageText: String,
        informativeText: String,
        primaryButtonTitle: String,
        secondaryButtonTitle: String? = nil
    ) -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = messageText
        alert.informativeText = informativeText
        alert.icon = updaterAlertIcon()

        let primaryButton = alert.addButton(withTitle: primaryButtonTitle)
        primaryButton.keyEquivalent = "\r"

        if let secondaryButtonTitle {
            let secondaryButton = alert.addButton(withTitle: secondaryButtonTitle)
            secondaryButton.keyEquivalent = "\u{1b}"
        }

        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }

    private func updaterAlertIcon() -> NSImage? {
        let iconURLs = [
            Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
            Bundle.main.url(forResource: "AppIcon", withExtension: "icns", subdirectory: "Resources"),
            Bundle.main.resourceURL?.appendingPathComponent("Resources/AppIcon.icns")
        ].compactMap { $0 }

        if let iconURL = iconURLs.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
           let icon = NSImage(contentsOf: iconURL),
           icon.isValid {
            return sizedAlertIcon(icon)
        }

        if let appIcon = NSApp.applicationIconImage, appIcon.isValid {
            return sizedAlertIcon(appIcon)
        }

        return nil
    }

    private func sizedAlertIcon(_ icon: NSImage) -> NSImage {
        guard let copy = icon.copy() as? NSImage else { return icon }
        copy.size = NSSize(width: 64, height: 64)
        return copy
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
