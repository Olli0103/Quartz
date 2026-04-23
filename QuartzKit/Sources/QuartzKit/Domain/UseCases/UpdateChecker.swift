import Foundation
import os

/// Checks GitHub Releases for new versions of Quartz.
///
/// Compares the current app version against the latest GitHub release tag.
/// Non-blocking, runs in the background, and caches results for 24 hours.
public actor UpdateChecker {
    public static let shared = UpdateChecker()

    public struct ReleaseInfo: Sendable {
        public let version: String
        public let downloadURL: URL
        public let releaseNotesURL: URL
        public let publishedAt: Date?
    }

    private static let repoOwner = "Olli0103"
    private static let repoName = "Quartz"
    private static let cacheKey = "quartz.lastUpdateCheck"
    private static let cacheVersionKey = "quartz.latestKnownVersion"
    private static let cacheDuration: TimeInterval = 86400 // 24h

    private let logger = Logger(subsystem: "app.quartz", category: "UpdateChecker")

    public init() {}

    /// Returns the latest release if it's newer than the current version.
    public func checkForUpdate() async -> ReleaseInfo? {
        let currentVersion = currentAppVersion()

        if let cached = cachedResult(), cached.version != currentVersion {
            return cached
        }

        guard let latest = await fetchLatestRelease() else { return nil }

        cacheResult(version: latest.version)

        if isNewer(latest.version, than: currentVersion) {
            return latest
        }
        return nil
    }

    /// Forces a check, ignoring cache.
    public func forceCheck() async -> ReleaseInfo? {
        UserDefaults.standard.removeObject(forKey: Self.cacheKey)
        return await checkForUpdate()
    }

    private func currentAppVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private func fetchLatestRelease() async -> ReleaseInfo? {
        let urlString = "https://api.github.com/repos/\(Self.repoOwner)/\(Self.repoName)/releases/latest"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

            let tagName = (json["tag_name"] as? String ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            let htmlURL = json["html_url"] as? String ?? ""

            var downloadURL: URL?
            if let assets = json["assets"] as? [[String: Any]] {
                for asset in assets {
                    if let name = asset["name"] as? String,
                       name.hasSuffix(".dmg"),
                       let urlStr = asset["browser_download_url"] as? String {
                        downloadURL = URL(string: urlStr)
                        break
                    }
                }
            }

            var publishedAt: Date?
            if let dateString = json["published_at"] as? String {
                let formatter = ISO8601DateFormatter()
                publishedAt = formatter.date(from: dateString)
            }

            return ReleaseInfo(
                version: tagName,
                downloadURL: downloadURL ?? URL(string: htmlURL)!,
                releaseNotesURL: URL(string: htmlURL)!,
                publishedAt: publishedAt
            )
        } catch {
            logger.error("Failed to check for updates: \(error.localizedDescription)")
            QuartzDiagnostics.error(
                category: "UpdateChecker",
                "Failed to check for updates: \(error.localizedDescription)"
            )
            return nil
        }
    }

    private func isNewer(_ remote: String, than local: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let localParts = local.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(remoteParts.count, localParts.count) {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let l = i < localParts.count ? localParts[i] : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false
    }

    private func cachedResult() -> ReleaseInfo? {
        let defaults = UserDefaults.standard
        guard let lastCheck = defaults.object(forKey: Self.cacheKey) as? Date,
              Date().timeIntervalSince(lastCheck) < Self.cacheDuration,
              let version = defaults.string(forKey: Self.cacheVersionKey) else {
            return nil
        }
        let releasesURL = URL(string: "https://github.com/\(Self.repoOwner)/\(Self.repoName)/releases/latest")!
        return ReleaseInfo(version: version, downloadURL: releasesURL, releaseNotesURL: releasesURL, publishedAt: nil)
    }

    private func cacheResult(version: String) {
        let defaults = UserDefaults.standard
        defaults.set(Date(), forKey: Self.cacheKey)
        defaults.set(version, forKey: Self.cacheVersionKey)
    }
}
