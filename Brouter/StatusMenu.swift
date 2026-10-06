import AppKit
import BrouterCore

/// The menu bar icon and its menu. The menu is rebuilt each time it opens, so it always reflects the
/// current config, recent links, default-browser and login-item state without observing any of them.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let store: ConfigStore
    private let recents: RecentLinks
    /// Set when the app is reopened so a `hide_icon` user can reach the menu; cleared on the next config change.
    private var revealed = false

    init(store: ConfigStore, recents: RecentLinks) {
        self.store = store
        self.recents = recents
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        refreshIcon()
    }

    func configDidChange() {
        revealed = false
        refreshIcon()
    }

    func reveal() {
        revealed = true
        refreshIcon()
    }

    /// A problem with the config always shows the icon, even with `hide_icon` set.
    private func refreshIcon() {
        let symbol = store.needsAttention ? "exclamationmark.triangle" : "arrow.triangle.branch"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Brouter")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.isVisible = store.needsAttention || revealed || !(store.config?.hideIcon ?? false)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        var items = statusLines()
        items += [
            .separator(),
            action("Open Config", #selector(openConfig), key: ","),
            action("Reveal Config in Finder", #selector(revealConfig)),
            action("Reload Config", #selector(reloadConfig), key: "r"),
            .separator(),
            recentLinks(),
            .separator(),
        ]
        if !DefaultBrowser.isBrouter {
            items.append(action("Set as Default Browser", #selector(setDefaultBrowser)))
        }
        items += [loginItem(), .separator(), action("Quit Brouter", #selector(quit), key: "q")]
        menu.items = items
    }

    // MARK: - Items

    private func statusLines() -> [NSMenuItem] {
        if let error = store.error {
            let fallback = store.config == nil ? "Opening all links in Safari" : "Using the last valid config"
            return [label("⚠︎ \(error)"), label(fallback)]
        }
        if !store.warnings.isEmpty {
            let count = store.warnings.count
            let item = NSMenuItem(title: "⚠︎ \(count) warning\(count == 1 ? "" : "s")", action: nil, keyEquivalent: "")
            item.submenu = submenu(store.warnings.map { label($0.description) })
            return [item]
        }
        let rules = store.config?.rules.count ?? 0
        return [label("Config OK · \(rules) rule\(rules == 1 ? "" : "s")")]
    }

    private func recentLinks() -> NSMenuItem {
        let links = recents.entries.map { entry in
            let item = action(entry.title, #selector(copyLink(_:)))
            item.representedObject = entry.decision.input.absoluteString
            item.toolTip = "Click to copy \(entry.decision.input.absoluteString)"
            return item
        }
        let item = NSMenuItem(title: "Recent Links", action: nil, keyEquivalent: "")
        item.submenu = submenu(links.isEmpty ? [label("No links yet")] : links)
        return item
    }

    private func loginItem() -> NSMenuItem {
        let status = LoginItem.status
        let title = status == .requiresApproval ? "Launch at Login (Needs Approval)" : "Launch at Login"
        let item = action(title, #selector(toggleLoginItem))
        item.state = status == .enabled ? .on : .off
        return item
    }

    private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    private func label(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func submenu(_ items: [NSMenuItem]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.items = items
        return menu
    }

    // MARK: - Actions

    /// Recreates the starter config if the file has been deleted, so there's always something to open.
    @objc private func openConfig() {
        if !store.fileExists {
            do {
                try store.createStarterConfig()
            } catch {
                NSAlert.show("Couldn't create the Brouter config", error.localizedDescription)
                return
            }
        }
        store.openInEditor()
    }

    @objc private func revealConfig() {
        store.revealInFinder()
    }

    @objc private func reloadConfig() {
        store.reload()
    }

    @objc private func copyLink(_ sender: NSMenuItem) {
        guard let link = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)
    }

    @objc private func setDefaultBrowser() {
        Task { await DefaultBrowser.request() }
    }

    @objc private func toggleLoginItem() {
        LoginItem.toggle()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
