import Foundation

/// A change made to the link after matching.
public enum Rewrite: Codable, Sendable, Equatable {
    case strippedParam(String)
    case schemeSwap(from: String, to: String)
    case container(String)

    private enum CodingKeys: String, CodingKey {
        case type, param, from, to, name
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "strip_param":
            self = try .strippedParam(container.decode(String.self, forKey: .param))
        case "scheme":
            self = try .schemeSwap(
                from: container.decode(String.self, forKey: .from),
                to: container.decode(String.self, forKey: .to)
            )
        case "container":
            self = try .container(container.decode(String.self, forKey: .name))
        case let other:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container, debugDescription: "Unknown rewrite type \(other)"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .strippedParam(param):
            try container.encode("strip_param", forKey: .type)
            try container.encode(param, forKey: .param)
        case let .schemeSwap(from, to):
            try container.encode("scheme", forKey: .type)
            try container.encode(from, forKey: .from)
            try container.encode(to, forKey: .to)
        case let .container(name):
            try container.encode("container", forKey: .type)
            try container.encode(name, forKey: .name)
        }
    }
}

enum Rewriter {
    /// Removes query parameters whose names match any of `patterns` (case-insensitive globs). Every other
    /// parameter keeps its exact original bytes, since re-encoding can change what a server receives.
    static func strip(_ url: URL, patterns: [String]) -> (URL, [Rewrite]) {
        var link = url.absoluteString
        guard let range = URLComponents(string: link)?.rangeOfQuery, !range.isEmpty else { return (url, []) }
        let query = link[range]

        let patterns = patterns.map { $0.lowercased() }
        var removed: [Rewrite] = []
        let kept = query.split(separator: "&", omittingEmptySubsequences: false).filter { pair in
            let rawName = String(pair.prefix { $0 != "=" })
            let name = (rawName.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? rawName)
                .lowercased()
            guard patterns.contains(where: { Glob.matches($0, name) }) else { return true }
            removed.append(.strippedParam(rawName))
            return false
        }
        guard !removed.isEmpty else { return (url, []) }

        // Splice the string directly: URLComponents' setters reject or re-encode malformed escapes like `%zz`.
        if kept.isEmpty {
            link.removeSubrange(link.index(before: range.lowerBound) ..< range.upperBound)
        } else {
            link.replaceSubrange(range, with: kept.joined(separator: "&"))
        }
        return (URL(string: link) ?? url, removed)
    }

    /// Replaces only the scheme, keeping host, path, query and fragment intact.
    static func swapScheme(_ url: URL, to scheme: String) -> (URL, [Rewrite]) {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let current = components.scheme, current.lowercased() != scheme.lowercased()
        else { return (url, []) }
        components.scheme = scheme
        guard let swapped = components.url else { return (url, []) }
        return (swapped, [.schemeSwap(from: current, to: scheme)])
    }

    /// Wraps the link for the "Open external links in a container" Firefox extension, which registers
    /// `ext+container:`. Both parts are encoded like JavaScript's `encodeURIComponent`, which the extension reads.
    static func wrapInContainer(_ url: URL, name: String) -> (URL, [Rewrite]) {
        guard let wrapped = URL(string: "ext+container:name=\(encode(name))&url=\(encode(url.absoluteString))") else {
            return (url, [])
        }
        return (wrapped, [.container(name)])
    }

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()"
    )

    private static func encode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? text
    }
}
