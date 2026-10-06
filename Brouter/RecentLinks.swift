import BrouterCore
import Foundation

/// The last few routed links, newest first. Held in memory only and never written to disk.
@MainActor
final class RecentLinks {
    struct Entry {
        var decision: Decision
        /// The app the link was actually handed to.
        var app: ResolvedApp

        /// e.g. `github.com → Google Chrome (rule 2)`.
        var title: String {
            let host = decision.input.host(percentEncoded: false) ?? decision.input.absoluteString
            let source = decision.fallback ? "fallback" : decision.rule.map { "rule \($0)" } ?? "default"
            return "\(host) → \(app.name) (\(source))"
        }
    }

    static let capacity = 10

    private(set) var entries: [Entry] = []

    func record(_ decision: Decision, openedIn app: ResolvedApp) {
        entries.insert(Entry(decision: decision, app: app), at: 0)
        if entries.count > Self.capacity {
            entries.removeLast()
        }
    }
}
