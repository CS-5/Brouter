import AppKit
import BrouterCore

/// The live config: the last version that loaded cleanly, plus any problem with the file as it is now.
/// Reloads on its own whenever the file changes.
@MainActor
final class ConfigStore {
    let url: URL
    /// The last config that loaded without errors; kept while the file on disk is broken.
    private(set) var config: Config?
    private(set) var error: ConfigError?
    private(set) var warnings: [ConfigWarning] = []
    var onChange: (() -> Void)?

    private var sources: [any DispatchSourceFileSystemObject] = []
    private var pendingReload: Task<Void, Never>?

    /// Until a config has loaded once there is no trustworthy default, so links go to Safari untouched.
    private static let safariOnly = Config(defaultApp: "com.apple.Safari", stripTracking: false)

    init(url: URL = ConfigLoader.defaultURL) {
        self.url = url
        load()
        watch()
    }

    var needsAttention: Bool {
        error != nil || !warnings.isEmpty
    }

    var fileExists: Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    var router: Router {
        Router(config: config ?? Self.safariOnly, apps: WorkspaceAppResolver())
    }

    func reload() {
        pendingReload?.cancel()
        load()
        watch()
        onChange?()
    }

    /// Writes the commented starter config, using the current default browser (unless that's already Brouter)
    /// as `default`. Never overwrites an existing file.
    func createStarterConfig() throws {
        let resolver = WorkspaceAppResolver()
        let previousDefault = resolver.defaultBrowser().flatMap {
            $0.bundleID == Bundle.main.bundleIdentifier ? nil : $0
        }
        let contents = StarterConfig.make(browsers: resolver.installedBrowsers(), previousDefault: previousDefault)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url, options: .withoutOverwriting)
        reload()
    }

    /// Opens the config in the app registered for its file type, or TextEdit when there is none.
    func openInEditor() {
        let workspace = NSWorkspace.shared
        guard let editor = workspace.urlForApplication(toOpen: url)
            ?? workspace.urlForApplication(withBundleIdentifier: "com.apple.TextEdit")
        else { return }
        workspace.open([url], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([fileExists ? url : url.deletingLastPathComponent()])
    }

    private func load() {
        do {
            let loaded = try ConfigLoader.load(from: url)
            config = loaded
            error = nil
            warnings = ConfigLoader.warnings(for: loaded, apps: WorkspaceAppResolver())
        } catch {
            self.error = error
        }
    }

    /// Watches the config's directory, which catches editors that save by replacing the file, and the file
    /// itself, which catches in-place writes. While the directory doesn't exist, the nearest existing ancestor
    /// is watched instead so its creation is noticed. Every event re-arms the watchers, since a replaced file
    /// or recreated directory is a new inode.
    private func watch() {
        for source in sources {
            source.cancel()
        }
        sources = []

        let directory = url.deletingLastPathComponent()
        var watched = directory
        var descriptor = Darwin.open(watched.path(percentEncoded: false), O_EVTONLY)
        while descriptor < 0, watched.pathComponents.count > 1 {
            watched = watched.deletingLastPathComponent()
            descriptor = Darwin.open(watched.path(percentEncoded: false), O_EVTONLY)
        }
        if descriptor >= 0 {
            sources.append(makeSource(descriptor))
        }
        if watched == directory {
            let file = Darwin.open(url.path(percentEncoded: false), O_EVTONLY)
            if file >= 0 {
                sources.append(makeSource(file))
            }
        }
    }

    private func makeSource(_ descriptor: Int32) -> any DispatchSourceFileSystemObject {
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .extend, .delete, .rename], queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleReload() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return source
    }

    /// Editors often touch the file several times per save; wait for them to settle before reloading.
    private func scheduleReload() {
        pendingReload?.cancel()
        pendingReload = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }
}
