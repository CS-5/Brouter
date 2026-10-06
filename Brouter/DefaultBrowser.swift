import AppKit

@MainActor
enum DefaultBrowser {
    private static let probeURL = URL(string: "http://example.com")!

    static var isBrouter: Bool {
        guard let handler = NSWorkspace.shared.urlForApplication(toOpen: probeURL) else { return false }
        return Bundle(url: handler)?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    /// Asks macOS to make Brouter the default browser. macOS confirms with the user itself; declining isn't
    /// treated as an error.
    static func request() async {
        do {
            for scheme in ["http", "https"] {
                try await NSWorkspace.shared.setDefaultApplication(
                    at: Bundle.main.bundleURL, toOpenURLsWithScheme: scheme
                )
            }
        } catch CocoaError.userCancelled {
            return
        } catch {
            NSAlert.show("Couldn't set Brouter as the default browser", error.localizedDescription)
        }
    }
}
