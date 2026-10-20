import AppKit
import BrouterCore
import os

private let log = Logger(subsystem: "com.carsonseese.Brouter", category: "links")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = ConfigStore()
    private let recents = RecentLinks()
    private var statusMenu: StatusMenu?

    /// Registered before launch finishes so the link that launched the app isn't missed. A raw Apple Event
    /// handler is used instead of `application(_:open:)` because only the event carries the sender's PID.
    func applicationWillFinishLaunching(_: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_: Notification) {
        let statusMenu = StatusMenu(store: store, recents: recents)
        self.statusMenu = statusMenu
        store.onChange = { [weak statusMenu] in statusMenu?.configDidChange() }
        LoginItem.enableByDefault()

        if store.error?.kind == .notFound {
            firstRun()
        }
    }

    /// Opening the app again (e.g. from Finder) brings back an icon hidden by `hide_icon`.
    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        statusMenu?.reveal()
        return false
    }

    /// HTML files opened with Brouter. Implemented instead of `application(_:open:)`, which would make AppKit
    /// install its own GetURL handler and lose the sender of web links.
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let opener = Self.opener(from: NSWorkspace.shared.frontmostApplication)
        for filename in filenames {
            route(URL(filePath: filename), opener: opener)
        }
        sender.reply(toOpenOrPrint: .success)
    }

    func applicationSupportsSecureRestorableState(_: NSApplication) -> Bool {
        true
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReply _: NSAppleEventDescriptor) {
        guard let link = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue else {
            log.fault("Received a GetURL event without a link")
            return
        }
        guard let url = URL(string: link, encodingInvalidCharacters: true) else {
            // No app can be handed something that isn't a URL, so tell the user rather than drop the click.
            log.fault("Couldn't parse link \(link, privacy: .private)")
            NSAlert.show("Brouter couldn't open this link because it isn't a valid URL", link)
            return
        }
        route(url, opener: Self.opener(of: event))
    }

    private func route(_ url: URL, opener: Opener?) {
        let decision = store.router.route(url, opener: opener)
        let app = Launcher.open(decision)
        recents.record(decision, openedIn: app)
    }

    /// The sending app when it's a real app bundle; otherwise (e.g. the `open` command run from Terminal)
    /// the frontmost app, which is where the user clicked.
    private static func opener(of event: NSAppleEventDescriptor) -> Opener? {
        let pid = event.attributeDescriptor(forKeyword: keySenderPIDAttr)?.int32Value ?? 0
        let sender = NSRunningApplication(processIdentifier: pid)
        let isAppBundle = sender?.bundleURL?.pathExtension == "app"
        let isSelf = pid == ProcessInfo.processInfo.processIdentifier
        return opener(from: isAppBundle && !isSelf ? sender : NSWorkspace.shared.frontmostApplication)
    }

    /// Named the same way `brouter test --opener` resolves apps, so CLI results match real clicks.
    private static func opener(from app: NSRunningApplication?) -> Opener? {
        guard let app else { return nil }
        if let opener = app.bundleURL.flatMap(WorkspaceAppResolver.opener(at:)) {
            return opener
        }
        return Opener(name: app.localizedName, bundleID: app.bundleIdentifier)
    }

    /// Writes the starter config (seeded with the current default browser), asks to become the default
    /// browser, then opens the config for editing.
    private func firstRun() {
        do {
            try store.createStarterConfig()
        } catch {
            NSAlert.show("Couldn't create the Brouter config", error.localizedDescription)
            return
        }
        Task {
            if !DefaultBrowser.isBrouter {
                await DefaultBrowser.request()
            }
            store.openInEditor()
        }
    }
}

extension NSAlert {
    static func show(_ message: String, _ information: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = information
        alert.alertStyle = .warning
        NSApp.activate()
        alert.runModal()
    }
}
