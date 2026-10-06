import AppKit
import BrouterCore

/// Finds installed apps through Launch Services, falling back to the standard Applications folders.
struct WorkspaceAppResolver: AppResolving {
    private static let searchDirectories: [URL] = [
        URL(filePath: "/Applications"),
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications"),
        URL(filePath: "/System/Applications"),
    ]

    private static let probeURL = URL(string: "https://example.com")!

    var ownBundleID: String? {
        Bundle.main.bundleIdentifier
    }

    func resolve(_ nameOrBundleID: String) -> ResolvedApp? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: nameOrBundleID) {
            return Self.app(at: url)
        }
        let inFolders = Self.searchDirectories
            .map { $0.appending(path: "\(nameOrBundleID).app") }
            .filter { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
        let candidates = NSWorkspace.shared.urlsForApplications(toOpen: Self.probeURL) + inFolders
        let match = candidates.first { url in
            Self.names(of: url).contains { $0.caseInsensitiveCompare(nameOrBundleID) == .orderedSame }
        }
        return match.flatMap(Self.app(at:))
    }

    /// Apps registered to open web links, excluding Brouter itself.
    func installedBrowsers() -> [ResolvedApp] {
        var seen = Set<String>()
        return NSWorkspace.shared.urlsForApplications(toOpen: Self.probeURL)
            .compactMap(Self.app(at:))
            .filter { !isSelf($0) && seen.insert($0.bundleID ?? $0.name).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The app currently handling web links.
    func defaultBrowser() -> ResolvedApp? {
        NSWorkspace.shared.urlForApplication(toOpen: Self.probeURL).flatMap(Self.app(at:))
    }

    /// Uses the Finder name (e.g. "Visual Studio Code") rather than the often terser bundle name ("Code").
    static func app(at url: URL) -> ResolvedApp? {
        guard let bundle = Bundle(url: url) else { return nil }
        let name = url.deletingPathExtension().lastPathComponent
        return ResolvedApp(name: name, bundleID: bundle.bundleIdentifier, url: url)
    }

    /// The app at `url` as a link opener, carrying every name `resolve` accepts so rules match it the same way.
    static func opener(at url: URL) -> Opener? {
        guard let app = app(at: url) else { return nil }
        let alternates = names(of: url).filter { $0 != app.name }
        return Opener(name: app.name, bundleID: app.bundleID, alternateNames: Array(Set(alternates)).sorted())
    }

    /// Finder name plus the bundle's own names, so "Code" and "Visual Studio Code" both resolve.
    private static func names(of url: URL) -> [String] {
        let info = Bundle(url: url)?.infoDictionary ?? [:]
        return [url.deletingPathExtension().lastPathComponent]
            + ["CFBundleDisplayName", "CFBundleName"].compactMap { info[$0] as? String }
    }
}
