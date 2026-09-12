import Foundation
import AppKit
import Combine

class GitHubUpdater: ObservableObject {
    static let shared = GitHubUpdater()
    private let repo = "iddictive/Whisper-Killer"
    private static let productionBundleIdentifier = "com.whisperkiller.app"
    private static let installedApplicationURL = URL(fileURLWithPath: "/Applications/WhisperKiller.app")
    let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "3.0"
    let isAvailable = GitHubUpdater.isAvailable(
        bundleIdentifier: Bundle.main.bundleIdentifier,
        bundleURL: Bundle.main.bundleURL
    )

    @Published var isChecking = false
    @Published var updateAvailable = false
    @Published var latestVersion: String?
    @Published var downloadUrl: String?
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var error: String?

    private var downloadTask: URLSessionDownloadTask?
    private var observation: NSKeyValueObservation?
    private var latestReleaseNotes: [String] = []
    private var manualFeedbackRequested = false

    static func isAvailable(bundleIdentifier: String?, bundleURL: URL) -> Bool {
        guard bundleIdentifier == productionBundleIdentifier else { return false }
        return bundleURL.standardizedFileURL == installedApplicationURL.standardizedFileURL
    }

    func checkForUpdates(manual: Bool = false) {
        if manual {
            manualFeedbackRequested = true
        }

        guard isAvailable else {
            if manual {
                manualFeedbackRequested = false
                _ = runUpdaterAlert(
                    messageText: L.tr("Updates unavailable", "Проверка недоступна"),
                    informativeText: L.tr(
                        "Update checks are available from the installed WhisperKiller app.",
                        "Проверка обновлений доступна в установленном приложении WhisperKiller."
                    ),
                    primaryButtonTitle: L.tr("OK", "ОК")
                )
            }
            return
        }
        guard !isChecking else { return }

        let updateSettings = Storage.shared.loadSettings()
        if !manual && !updateSettings.automaticallyChecksForUpdates { return }

        isChecking = true
        error = nil

        print("🔍 Checking for updates at https://api.github.com/repos/\(repo)/releases/latest")

        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("WhisperKillerUpdater", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }

                guard let data, error == nil else {
                    self.finishCheckWithError(
                        error?.localizedDescription ?? L.tr("Network error", "Ошибка сети")
                    )
                    return
                }

                do {
                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 else {
                        let statusCode = (response as? HTTPURLResponse)?.statusCode
                        throw UpdateCheckError.invalidResponse(statusCode)
                    }

                    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let tagName = json["tag_name"] as? String,
                          !tagName.isEmpty else {
                        throw UpdateCheckError.invalidPayload
                    }

                    self.handleLatestRelease(json: json, tagName: tagName)
                } catch {
                    self.finishCheckWithError(error.localizedDescription)
                }
            }
        }.resume()
    }

    private func compareVersions(current: String, latest: String) -> Bool {
        return latest.compare(current, options: .numeric) == .orderedDescending
    }

    private func handleLatestRelease(json: [String: Any], tagName: String) {
        let latest = tagName.replacingOccurrences(
            of: "v",
            with: "",
            options: [.anchored, .caseInsensitive]
        )
        let hasUpdate = compareVersions(current: currentVersion, latest: latest)
        let assets = json["assets"] as? [[String: Any]]
        let dmgAsset = assets?.first(where: { ($0["name"] as? String)?.hasSuffix(".dmg") == true })
        let dmgURL = dmgAsset?["browser_download_url"] as? String
        let releaseBody = json["body"] as? String ?? ""
        let embeddedNotes = ChangelogManager.summaryLines(from: releaseBody)

        latestVersion = latest
        updateAvailable = hasUpdate
        downloadUrl = dmgURL

        if hasUpdate && dmgURL == nil {
            finishCheckWithError(
                L.tr(
                    "Version \(latest) does not include a downloadable DMG.",
                    "В релизе \(latest) нет доступного DMG."
                )
            )
            return
        }

        guard embeddedNotes.isEmpty else {
            completeCheck(latest: latest, hasUpdate: hasUpdate, notes: embeddedNotes)
            return
        }

        guard manualFeedbackRequested || hasUpdate else {
            completeCheck(latest: latest, hasUpdate: hasUpdate, notes: [])
            return
        }

        fetchChangelogNotes(tagName: tagName, version: latest) { [weak self] notes in
            self?.completeCheck(latest: latest, hasUpdate: hasUpdate, notes: notes)
        }
    }

    private func fetchChangelogNotes(
        tagName: String,
        version: String,
        completion: @escaping ([String]) -> Void
    ) {
        let encodedTag = tagName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tagName
        guard let url = URL(
            string: "https://raw.githubusercontent.com/\(repo)/\(encodedTag)/CHANGELOG.md"
        ) else {
            completion([])
            return
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("WhisperKillerUpdater", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { data, response, _ in
            let markdown: String?
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200,
               let data {
                markdown = String(data: data, encoding: .utf8)
            } else {
                markdown = nil
            }

            let notes = markdown.map {
                ChangelogManager.releaseNotes(from: $0, version: version)
            } ?? []

            DispatchQueue.main.async {
                completion(notes)
            }
        }.resume()
    }

    private func completeCheck(latest: String, hasUpdate: Bool, notes: [String]) {
        isChecking = false
        latestReleaseNotes = notes

        let shouldShowManualFeedback = manualFeedbackRequested
        manualFeedbackRequested = false
        let automaticallyDownloadsUpdates = Storage.shared.loadSettings().automaticallyDownloadsUpdates

        if hasUpdate {
            if shouldShowManualFeedback {
                showUpdateAlert(version: latest, releaseNotes: notes)
            } else if automaticallyDownloadsUpdates {
                startDownload()
            }
        } else if shouldShowManualFeedback {
            showUpToDateAlert(releaseNotes: notes)
        }
    }

    private func finishCheckWithError(_ message: String) {
        isChecking = false
        updateAvailable = false
        downloadUrl = nil
        error = message

        let shouldShowManualFeedback = manualFeedbackRequested
        manualFeedbackRequested = false
        guard shouldShowManualFeedback else { return }

        _ = runUpdaterAlert(
            messageText: L.tr("Couldn’t check for updates", "Не удалось проверить обновления"),
            informativeText: message,
            primaryButtonTitle: L.tr("OK", "ОК")
        )
    }

    private func showUpToDateAlert(releaseNotes: [String]) {
        _ = runUpdaterAlert(
            messageText: L.tr("You’re up to date", "Обновлений нет"),
            informativeText: informativeText(
                base: L.tr(
                    "WhisperKiller \(currentVersion) is the latest version.",
                    "Установлена последняя версия WhisperKiller \(currentVersion)."
                ),
                releaseNotes: releaseNotes
            ),
            primaryButtonTitle: L.tr("OK", "ОК"),
            minimumContentWidth: releaseNotes.isEmpty ? nil : 520
        )
    }

    private func showUpdateAlert(version: String, releaseNotes: [String]) {
        let response = runUpdaterAlert(
            messageText: L.tr("Update Available", "Доступно обновление"),
            informativeText: informativeText(
                base: L.tr(
                    "WhisperKiller \(version) is ready to download.",
                    "WhisperKiller \(version) готов к загрузке."
                ),
                releaseNotes: releaseNotes
            ),
            primaryButtonTitle: L.tr("Download & Install", "Скачать и установить"),
            secondaryButtonTitle: L.tr("Later", "Позже"),
            minimumContentWidth: releaseNotes.isEmpty ? nil : 520
        )

        if response == .alertFirstButtonReturn {
            startDownload()
        }
    }

    func startDownload() {
        guard isAvailable else { return }
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
        guard isAvailable else { return }
        // Show install prompt if it was a background download
        DispatchQueue.main.async {
            let version = self.latestVersion ?? ""
            let response = self.runUpdaterAlert(
                messageText: L.tr("Installation Ready", "Готово к установке"),
                informativeText: self.informativeText(
                    base: L.tr(
                        "WhisperKiller \(version) has been downloaded. The app will close, install the update, and relaunch.",
                        "WhisperKiller \(version) загружен. Приложение закроется, установит обновление и запустится снова."
                    ),
                    releaseNotes: self.latestReleaseNotes
                ),
                primaryButtonTitle: L.tr("Install & Relaunch", "Установить и перезапустить"),
                secondaryButtonTitle: L.tr("Later", "Позже"),
                minimumContentWidth: self.latestReleaseNotes.isEmpty ? nil : 520
            )

            if response == .alertFirstButtonReturn {
                self.runInstallScript(dmgPath: dmgPath)
            }
        }
    }

    private func informativeText(base: String, releaseNotes: [String]) -> String {
        guard !releaseNotes.isEmpty else { return base }

        let heading = L.tr("What’s new:", "Что нового:")
        let bullets = releaseNotes.map { "• \($0)" }.joined(separator: "\n")
        return "\(base)\n\n\(heading)\n\(bullets)"
    }

    @discardableResult
    private func runUpdaterAlert(
        messageText: String,
        informativeText: String,
        primaryButtonTitle: String,
        secondaryButtonTitle: String? = nil,
        minimumContentWidth: CGFloat? = nil
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

        if let minimumContentWidth {
            alert.accessoryView = NSView(
                frame: NSRect(x: 0, y: 0, width: minimumContentWidth, height: 0)
            )
            alert.layout()
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
        guard expectedVersion.range(
            of: #"^\d+(?:\.\d+)+$"#,
            options: .regularExpression
        ) != nil else {
            error = L.tr("Invalid update version.", "Некорректная версия обновления.")
            return
        }
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

        stagedBundleID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$stagedAppPath/Contents/Info.plist" 2>/dev/null || true)"
        if [ "$stagedBundleID" != "com.whisperkiller.app" ]; then
            log "Staged app has unexpected bundle identifier: $stagedBundleID"
            exit 1
        fi

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

private enum UpdateCheckError: LocalizedError {
    case invalidResponse(Int?)
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let statusCode):
            if let statusCode {
                return L.tr(
                    "Update check failed (HTTP \(statusCode)).",
                    "Проверка обновлений завершилась ошибкой (HTTP \(statusCode))."
                )
            }
            return L.tr("Invalid update response.", "Некорректный ответ сервера обновлений.")
        case .invalidPayload:
            return L.tr("Invalid update response.", "Некорректный ответ сервера обновлений.")
        }
    }
}
