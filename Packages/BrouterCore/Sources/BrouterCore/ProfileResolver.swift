import Foundation

/// A browser profile as listed in the browser's own profile registry.
public struct BrowserProfile: Codable, Sendable, Equatable {
    /// The name shown in the browser's profile picker.
    public var name: String
    /// The on-disk profile directory name, e.g. `Profile 1`.
    public var directory: String
}

public enum ProfileError: Error, Sendable, Equatable, CustomStringConvertible {
    case unsupportedBrowser(String)
    case notFound(profile: String, browser: String, available: [String])

    public var description: String {
        switch self {
        case let .unsupportedBrowser(browser):
            "profiles aren't supported for \"\(browser)\""
        case let .notFound(profile, browser, available):
            "\"\(browser)\" has no profile \"\(profile)\""
                + (available.isEmpty ? "" : " (available: \(available.map { "\"\($0)\"" }.joined(separator: ", ")))")
        }
    }
}

/// Maps profile display names to the launch arguments that select them.
public struct ProfileResolver: Sendable {
    enum Family: Sendable {
        /// Profiles listed in `<dir>/Local State`; selected with `--profile-directory=<dir>`.
        case chromium(String)
        /// Profiles listed in `<dir>/profiles.ini`; selected with `-P <name>`.
        case firefox(String)
    }

    static let families: [String: Family] = [
        "com.google.Chrome": .chromium("Google/Chrome"),
        "com.brave.Browser": .chromium("BraveSoftware/Brave-Browser"),
        "com.microsoft.edgemac": .chromium("Microsoft Edge"),
        "com.vivaldi.Vivaldi": .chromium("Vivaldi"),
        "org.chromium.Chromium": .chromium("Chromium"),
        "org.mozilla.firefox": .firefox("Firefox"),
        "app.zen-browser.zen": .firefox("zen"),
    ]

    public let applicationSupport: URL

    public init(applicationSupport: URL = URL.applicationSupportDirectory) {
        self.applicationSupport = applicationSupport
    }

    public func supportsProfiles(bundleID: String) -> Bool {
        Self.families[bundleID] != nil
    }

    public func profiles(bundleID: String) -> [BrowserProfile] {
        switch Self.families[bundleID] {
        case let .chromium(dir): chromiumProfiles(dir)
        case let .firefox(dir): firefoxProfiles(dir)
        case nil: []
        }
    }

    /// Accepts a profile's display name (exact, then case-insensitive) or its raw directory name.
    public func resolve(_ profile: String, for app: ResolvedApp) -> Result<[String], ProfileError> {
        guard let bundleID = app.bundleID, let family = Self.families[bundleID] else {
            return .failure(.unsupportedBrowser(app.name))
        }
        let available = profiles(bundleID: bundleID)
        let match = available.first { $0.name == profile }
            ?? available.first { $0.name.caseInsensitiveCompare(profile) == .orderedSame }
            ?? available.first { $0.directory == profile }
        guard let match else {
            return .failure(.notFound(profile: profile, browser: app.name, available: available.map(\.name)))
        }
        return switch family {
        case .chromium: .success(["--profile-directory=\(match.directory)"])
        case .firefox: .success(["-P", match.name])
        }
    }

    private func chromiumProfiles(_ dir: String) -> [BrowserProfile] {
        let file = applicationSupport.appending(path: dir).appending(path: "Local State")
        guard let data = try? Data(contentsOf: file),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = root["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: Any]
        else { return [] }
        return cache.compactMap { directory, info in
            guard let name = (info as? [String: Any])?["name"] as? String else { return nil }
            return BrowserProfile(name: name, directory: directory)
        }
        .sorted { $0.directory.localizedStandardCompare($1.directory) == .orderedAscending }
    }

    private func firefoxProfiles(_ dir: String) -> [BrowserProfile] {
        let file = applicationSupport.appending(path: dir).appending(path: "profiles.ini")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }

        var profiles: [BrowserProfile] = []
        var section = ""
        var fields: [String: String] = [:]
        func flush() {
            if section.hasPrefix("Profile"), let name = fields["Name"], let path = fields["Path"] {
                profiles.append(BrowserProfile(name: name, directory: URL(filePath: path).lastPathComponent))
            }
            fields = [:]
        }
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("["), line.hasSuffix("]") {
                flush()
                section = String(line.dropFirst().dropLast())
            } else if let equals = line.firstIndex(of: "="), !line.hasPrefix(";"), !line.hasPrefix("#") {
                fields[String(line[..<equals])] = String(line[line.index(after: equals)...])
            }
        }
        flush()
        return profiles
    }
}
