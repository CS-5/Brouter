import AppKit
import BrouterCore
import os

private let log = Logger(subsystem: "com.carsonseese.Brouter", category: "launch")

@MainActor
enum Launcher {
    /// Opens the decision's link and returns the app it was handed to. Links whose app couldn't be used
    /// (missing, or Brouter itself, which would loop) open in Safari, as do links the chosen app fails to open.
    @discardableResult
    static func open(_ decision: Decision) -> ResolvedApp {
        guard let app = decision.app, !WorkspaceAppResolver().isSelf(app) else {
            openInSafari(safariURL(for: decision))
            return safari
        }
        let url = decision.url
        let configuration = NSWorkspace.OpenConfiguration()
        let completion: @Sendable (NSRunningApplication?, (any Error)?) -> Void = { _, error in
            guard let error else { return }
            log.error("Couldn't open link in \(app.name, privacy: .public): \(error.localizedDescription)")
            Task { @MainActor in
                if app.bundleID != safari.bundleID {
                    openInSafari(safariURL(for: decision))
                }
            }
        }

        if decision.arguments.isEmpty {
            NSWorkspace.shared.open(
                [url],
                withApplicationAt: app.url,
                configuration: configuration,
                completionHandler: completion
            )
        } else {
            // Profile arguments only take effect on launch, so start a new instance the way `open -n --args`
            // does; Chromium and Firefox hand the URL over to the already running instance.
            configuration.arguments = decision.arguments + [url.absoluteString]
            configuration.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: app.url, configuration: configuration, completionHandler: completion)
        }
        return app
    }

    /// Keeps tracking removal but undoes a scheme swap, which only makes sense for the intended app.
    private static func safariURL(for decision: Decision) -> URL {
        decision.url.scheme == decision.input.scheme ? decision.url : decision.input
    }

    private static func openInSafari(_ url: URL) {
        NSWorkspace.shared
            .open([url], withApplicationAt: safari.url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if let error {
                    log.fault("Couldn't open link in Safari: \(error.localizedDescription)")
                }
            }
    }

    private static var safari: ResolvedApp {
        WorkspaceAppResolver().resolve("com.apple.Safari")
            ?? ResolvedApp(name: "Safari", bundleID: "com.apple.Safari", url: URL(filePath: "/Applications/Safari.app"))
    }
}
