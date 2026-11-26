import AppKit
import CryptoKit
import Foundation

/// Update checks against GitHub Releases (the repo is public, releases
/// carry one asset: SilverNotes-app-vX.Y.Z.zip with the app at its root).
///
/// Nothing here ever downloads or installs on its own: check() only reads,
/// and downloadAndInstall() runs solely from the Settings button click.
/// The install mirrors the sibling app's proven shape — download, verify
/// the release's SHA-256, unpack, then hand the bundle swap to a detached
/// shell script so the app can quit before its own bundle is replaced.
final class UpdateChecker {

    static let shared = UpdateChecker()

    private init() {}

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// The last newer release a check found, if any — the status menu
    /// reads this to badge its "Check for Updates…" item.
    private(set) var availableUpdate: (version: String, downloadURL: URL, digest: String?)?

    enum CheckResult {
        case upToDate
        case updateAvailable(version: String)
        case failed(String)
    }

    private let latestReleaseURL = URL(string: "https://api.github.com/repos/femisowems/silvernotes-app/releases/latest")!

    // MARK: Check

    func check(completion: @escaping (CheckResult) -> Void) {
        var request = URLRequest(url: latestReleaseURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("SilverNotes/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            var newAvailable: (version: String, downloadURL: URL, digest: String?)? = nil
            let result: CheckResult
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 200
            if error != nil {
                result = .failed("Couldn't check — no connection.")
            } else if statusCode == 200, let data = data, let release = self.parseLatestRelease(data) {
                if self.isNewer(release.version, than: self.currentVersion) {
                    newAvailable = release
                    result = .updateAvailable(version: release.version)
                } else {
                    result = .upToDate
                }
            } else {
                result = .failed("Couldn't read the release info.")
            }
            DispatchQueue.main.async {
                self.availableUpdate = newAvailable
                completion(result)
            }
        }.resume()
    }

    private func parseLatestRelease(_ data: Data) -> (version: String, downloadURL: URL, digest: String?)? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var tag = json["tag_name"] as? String,
              let assets = json["assets"] as? [[String: Any]] else { return nil }
        if tag.hasPrefix("v") { tag.removeFirst() }
        guard !tag.isEmpty else { return nil }
        for asset in assets {
            guard let name = asset["name"] as? String,
                  name.hasPrefix("SilverNotes-app-"), name.hasSuffix(".zip"),
                  let urlString = asset["browser_download_url"] as? String,
                  let url = URL(string: urlString) else { continue }
            var digest: String? = nil
            if let raw = asset["digest"] as? String, raw.hasPrefix("sha256:") {
                digest = String(raw.dropFirst("sha256:".count))
            }
            return (version: tag, downloadURL: url, digest: digest)
        }
        return nil
    }

    /// Numeric dotted comparison: missing components count as 0, so
    /// "0.3" and "0.3.0" are equal and "0.10.0" beats "0.9.0".
    private func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: Download & install

    /// completion(nil) means the swap script is running and the app is
    /// about to quit to let it work; any non-nil value is a user-facing
    /// error and nothing was changed.
    func downloadAndInstall(completion: @escaping (String?) -> Void) {
        guard let update = availableUpdate else {
            completion("No update is ready to install.")
            return
        }
        // The swap replaces the bundle in place, which only works where
        // the app's parent folder is writable — not from a read-only
        // disk image or a folder the user can't modify.
        let bundlePath = Bundle.main.bundlePath
        let parent = (bundlePath as NSString).deletingLastPathComponent
        guard FileManager.default.isWritableFile(atPath: parent) else {
            completion("Move SilverNotes to your Applications folder, then try the update again.")
            return
        }

        let fileManager = FileManager.default
        let workDir = fileManager.temporaryDirectory
            .appendingPathComponent("SilverNotes-Update-\(UUID().uuidString)", isDirectory: true)

        var request = URLRequest(url: update.downloadURL, timeoutInterval: 60)
        request.setValue("SilverNotes/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.downloadTask(with: request) { [weak self] tempURL, _, error in
            guard let self = self else { return }
            func fail(_ message: String) {
                try? fileManager.removeItem(at: workDir)
                DispatchQueue.main.async { completion(message) }
            }
            guard let tempURL = tempURL, error == nil else {
                fail("The download didn't finish — try again.")
                return
            }
            do {
                try fileManager.createDirectory(at: workDir, withIntermediateDirectories: true)
                let zipURL = workDir.appendingPathComponent("update.zip")
                try fileManager.moveItem(at: tempURL, to: zipURL)

                // Verify before trusting anything inside the zip, when
                // the release published a digest.
                if let expected = update.digest {
                    guard let actual = self.sha256Hex(of: zipURL),
                          actual.lowercased() == expected.lowercased() else {
                        fail("The download didn't verify — nothing was installed.")
                        return
                    }
                }

                let extractDir = workDir.appendingPathComponent("extracted", isDirectory: true)
                try fileManager.createDirectory(at: extractDir, withIntermediateDirectories: true)
                let ditto = Process()
                ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                ditto.arguments = ["-x", "-k", zipURL.path, extractDir.path]
                try ditto.run()
                ditto.waitUntilExit()
                let newApp = extractDir.appendingPathComponent("SilverNotes.app")
                guard ditto.terminationStatus == 0,
                      fileManager.fileExists(atPath: newApp.path) else {
                    fail("The update couldn't be unpacked — nothing was installed.")
                    return
                }

                try self.launchSwapScript(newAppPath: newApp.path, bundlePath: bundlePath, workDir: workDir)
            } catch {
                fail("The update couldn't be installed — nothing was changed.")
                return
            }
            // The script waits for this process to exit before swapping,
            // so report success first (the UI shows "Restarting…"), then
            // quit and let it work.
            DispatchQueue.main.async { completion(nil) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { NSApp.terminate(nil) }
        }.resume()
    }

    private func sha256Hex(of fileURL: URL) -> String? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Writes the swap script into the work dir and starts it detached.
    /// The script outlives the app: it waits for our PID to exit, moves
    /// the current bundle aside as a backup, moves the new bundle in,
    /// and restores the backup if the new bundle doesn't land — then
    /// relaunches either way, so a failed swap still leaves a working app.
    private func launchSwapScript(newAppPath: String, bundlePath: String, workDir: URL) throws {
        func quoted(_ path: String) -> String {
            "\"" + path.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        let script = """
        #!/bin/sh
        APP_PATH=\(quoted(bundlePath))
        NEW_APP=\(quoted(newAppPath))
        BACKUP="$APP_PATH.backup"
        APP_PID=\(ProcessInfo.processInfo.processIdentifier)

        n=0
        while kill -0 "$APP_PID" 2>/dev/null; do
          n=$((n + 1))
          [ "$n" -ge 100 ] && break
          sleep 0.1
        done

        rm -rf "$BACKUP"
        if mv "$APP_PATH" "$BACKUP" && mv "$NEW_APP" "$APP_PATH" && [ -d "$APP_PATH" ]; then
          rm -rf "$BACKUP"
        elif [ ! -d "$APP_PATH" ] && [ -d "$BACKUP" ]; then
          mv "$BACKUP" "$APP_PATH"
        fi
        rm -rf \(quoted(workDir.path))
        /usr/bin/open "$APP_PATH"
        """
        let scriptURL = workDir.appendingPathComponent("swap.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [scriptURL.path]
        try process.run()
    }
}
