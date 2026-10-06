import Foundation

public enum MatchKey: String, Codable, Sendable {
    case host, path, url, regex, opener
}

/// The outcome of one match key within a rule.
public struct KeyTrace: Codable, Sendable, Equatable {
    public var key: MatchKey
    public var matched: Bool
    /// The pattern that matched, when `matched` is true.
    public var pattern: String?
    /// Why the key failed, when `matched` is false.
    public var reason: String?
}

/// The outcome of evaluating one rule against a link.
public struct RuleTrace: Codable, Sendable, Equatable {
    public var rule: Int
    public var matched: Bool
    public var keys: [KeyTrace]
}

enum Matcher {
    static func evaluate(_ rule: Rule, url: URL, opener: Opener?) -> RuleTrace {
        var keys: [KeyTrace] = []
        let full = url.absoluteString

        if !rule.host.isEmpty {
            let host = url.host(percentEncoded: false)?.lowercased()
            keys.append(check(.host, rule.host, actual: host.map { "\"\($0)\"" } ?? "no host") { pattern in
                guard let host else { return false }
                let pattern = pattern.lowercased()
                return host == pattern || host.hasSuffix("." + pattern)
            })
        }
        if !rule.path.isEmpty {
            let path = url.path(percentEncoded: true).isEmpty ? "/" : url.path(percentEncoded: true)
            keys.append(check(.path, rule.path, actual: "\"\(path)\"") { Glob.matches($0, path) })
        }
        if !rule.url.isEmpty {
            keys.append(check(.url, rule.url, actual: nil) { Glob.matches($0, full) })
        }
        if !rule.regex.isEmpty {
            let match = rule.regex.first { $0.matches(full) }
            keys.append(KeyTrace(
                key: .regex,
                matched: match != nil,
                pattern: match?.source,
                reason: match == nil ? "no match for \(quotedList(rule.regex.map(\.source)))" : nil
            ))
        }
        if !rule.opener.isEmpty {
            let candidates = opener?.identifiers.map { $0.lowercased() } ?? []
            keys.append(check(.opener, rule.opener, actual: opener?.displayName ?? "unknown") {
                candidates.contains($0.lowercased())
            })
        }

        return RuleTrace(rule: rule.number, matched: keys.allSatisfy(\.matched), keys: keys)
    }

    private static func check(
        _ key: MatchKey,
        _ patterns: [String],
        actual: String?,
        _ predicate: (String) -> Bool
    ) -> KeyTrace {
        if let hit = patterns.first(where: predicate) {
            return KeyTrace(key: key, matched: true, pattern: hit, reason: nil)
        }
        let wanted = "wanted \(quotedList(patterns))"
        return KeyTrace(key: key, matched: false, pattern: nil, reason: actual.map { "got \($0), \(wanted)" } ?? wanted)
    }

    private static func quotedList(_ values: [String]) -> String {
        values.map { "\"\($0)\"" }.joined(separator: " or ")
    }
}

/// Glob matching where `*` matches any run of characters (including `/`) and everything else is literal.
enum Glob {
    static func matches(_ pattern: String, _ text: String) -> Bool {
        let pattern = Array(pattern.unicodeScalars)
        let text = Array(text.unicodeScalars)
        var patternIndex = 0
        var textIndex = 0
        var starIndex: Int?
        var starTextIndex = 0

        while textIndex < text.count {
            if patternIndex < pattern.count, pattern[patternIndex] == "*" {
                starIndex = patternIndex
                starTextIndex = textIndex
                patternIndex += 1
            } else if patternIndex < pattern.count, pattern[patternIndex] == text[textIndex] {
                patternIndex += 1
                textIndex += 1
            } else if let star = starIndex {
                patternIndex = star + 1
                starTextIndex += 1
                textIndex = starTextIndex
            } else {
                return false
            }
        }
        while patternIndex < pattern.count, pattern[patternIndex] == "*" {
            patternIndex += 1
        }
        return patternIndex == pattern.count
    }
}
