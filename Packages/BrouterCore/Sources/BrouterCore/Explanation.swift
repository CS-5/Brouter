import Foundation

public extension Decision {
    /// A multi-line, human-readable account of every check and change behind this decision.
    var explanation: String {
        var lines = ["link:     \(input.absoluteString)", "opener:   \(opener?.displayName ?? "unknown")", ""]

        if trace.isEmpty {
            lines.append("no rules configured")
        }
        for result in trace {
            let keys = result.keys.map { key in
                key.matched
                    ? "\(key.key.rawValue) ✓ \(key.pattern ?? "")"
                    : "\(key.key.rawValue) ✗ (\(key.reason ?? ""))"
            }
            lines.append("rule \(result.rule): \(keys.joined(separator: ", "))\(result.matched ? "  → match" : "")")
        }
        if rule == nil, !trace.isEmpty {
            lines.append("no rule matched; using default")
        }
        lines.append("")

        if rewrites.isEmpty {
            lines.append("rewrites: none\(stripTracking ? "" : " (tracking stripping off)")")
        } else {
            lines.append("rewrites:")
            for rewrite in rewrites {
                switch rewrite {
                case let .strippedParam(name): lines.append("  stripped \(name)")
                case let .schemeSwap(from, to): lines.append("  scheme \(from) → \(to)")
                case let .container(name): lines.append("  container \(name)")
                }
            }
        }
        lines.append("")

        let source = rule.map { "rule \($0)" } ?? "default"
        let appText = app.map { app in "\(app.name)\(app.bundleID.map { " (\($0))" } ?? "")" } ?? "nothing"
        lines.append("open:     \(appText)  [\(fallback ? "fallback from \(source)" : source)]")
        lines.append("url:      \(url.absoluteString)")
        if let profile {
            lines.append("profile:  \(profile)  \(arguments.joined(separator: " "))")
        }
        for note in notes {
            lines.append("note:     \(note)")
        }
        return lines.joined(separator: "\n")
    }

    /// Pretty-printed JSON with stable key order.
    func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
