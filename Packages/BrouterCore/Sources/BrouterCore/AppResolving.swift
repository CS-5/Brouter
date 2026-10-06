import Foundation

/// An installed application located on disk.
public struct ResolvedApp: Codable, Sendable, Equatable {
    public var name: String
    public var bundleID: String?
    public var url: URL

    public init(name: String, bundleID: String?, url: URL) {
        self.name = name
        self.bundleID = bundleID
        self.url = url
    }
}

/// Looks up installed apps by bundle ID or display name. Implemented by the app layer so Core stays AppKit-free.
public protocol AppResolving: Sendable {
    func resolve(_ nameOrBundleID: String) -> ResolvedApp?
    /// Bundle ID of the running router. Links are never routed back to it, since that would loop.
    var ownBundleID: String? { get }
}

public extension AppResolving {
    var ownBundleID: String? {
        nil
    }

    /// Whether `app` is the router itself.
    func isSelf(_ app: ResolvedApp) -> Bool {
        app.bundleID != nil && app.bundleID == ownBundleID
    }
}

/// The app that asked to open a link.
public struct Opener: Codable, Sendable, Equatable {
    public var name: String?
    public var bundleID: String?
    /// Other names the app goes by, such as its bundle name ("Code" for "Visual Studio Code").
    public var alternateNames: [String]

    public init(name: String?, bundleID: String?, alternateNames: [String] = []) {
        self.name = name
        self.bundleID = bundleID
        self.alternateNames = alternateNames
    }

    /// Every name or ID a rule's `opener` may use to match this app.
    var identifiers: [String] {
        [name, bundleID].compactMap(\.self) + alternateNames
    }

    var displayName: String {
        switch (name, bundleID) {
        case let (name?, bundleID?): "\"\(name)\" (\(bundleID))"
        case let (name?, nil): "\"\(name)\""
        case let (nil, bundleID?): bundleID
        case (nil, nil): "unknown"
        }
    }
}
