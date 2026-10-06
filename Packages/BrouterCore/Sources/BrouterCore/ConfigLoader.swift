import Foundation
import TOMLDecoder

/// A config problem that prevents loading. Syntax errors carry a line; semantic errors carry a key path.
public struct ConfigError: Error, Codable, Sendable, Equatable, CustomStringConvertible {
    public enum Kind: String, Codable, Sendable {
        case notFound = "not_found"
        case unreadable
        case syntax
        case invalid
    }

    public var kind: Kind
    public var message: String
    public var line: Int?
    /// Key path such as `rules[3].regex`, with rules numbered from 1.
    public var path: String?

    public init(_ kind: Kind, _ message: String, line: Int? = nil, path: String? = nil) {
        self.kind = kind
        self.message = message
        self.line = line
        self.path = path
    }

    public var description: String {
        let location = [line.map { "line \($0)" }, path].compactMap(\.self).joined(separator: ", ")
        return location.isEmpty ? message : "\(location): \(message)"
    }
}

/// A config problem that doesn't prevent routing, such as a target app that isn't installed.
public struct ConfigWarning: Codable, Sendable, Equatable, CustomStringConvertible {
    public var path: String
    public var message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }

    public var description: String {
        "\(path): \(message)"
    }
}

public enum ConfigLoader {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(components: ".config", "brouter", "config.toml")
    }

    public static func load(from url: URL = defaultURL) throws(ConfigError) -> Config {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw ConfigError(.notFound, "no config file at \(url.path(percentEncoded: false))")
        }
        let source: String
        do {
            source = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ConfigError(
                .unreadable,
                "can't read \(url.path(percentEncoded: false)): \(error.localizedDescription)"
            )
        }
        return try parse(source)
    }

    public static func parse(_ source: String) throws(ConfigError) -> Config {
        let root: TOMLTable
        do {
            root = try TOMLTable(source: source)
        } catch {
            let (line, message) = error.split
            let cleaned = message.replacingOccurrences(of: "Syntax error: ", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            throw ConfigError(.syntax, "invalid TOML: \(cleaned)", line: line)
        }

        let reader = TableReader(table: root, path: "")
        try reader.rejectUnknownKeys(allowed: ["default", "strip_tracking", "strip_params", "hide_icon", "rules"])

        guard let defaultApp = try reader.string("default") else {
            throw ConfigError(.invalid, "required; set it to the app that opens links no rule matches", path: "default")
        }
        return try Config(
            defaultApp: defaultApp,
            stripTracking: reader.bool("strip_tracking") ?? true,
            stripParams: reader.strings("strip_params") ?? [],
            hideIcon: reader.bool("hide_icon") ?? false,
            rules: parseRules(root)
        )
    }

    /// Checks everything that depends on the machine rather than the file: installed apps and browser profiles.
    public static func warnings(
        for config: Config,
        apps: any AppResolving,
        profiles: ProfileResolver = ProfileResolver()
    ) -> [ConfigWarning] {
        var warnings: [ConfigWarning] = []
        func problem(_ name: String) -> String? {
            guard let app = apps.resolve(name) else { return "no app named \"\(name)\" found" }
            return apps.isSelf(app) ? "\"\(name)\" is Brouter itself" : nil
        }
        if let problem = problem(config.defaultApp) {
            warnings.append(ConfigWarning(path: "default", message: "\(problem); links will open in Safari"))
        }
        for rule in config.rules {
            let path = "rules[\(rule.number)]"
            if let problem = problem(rule.open) {
                warnings.append(ConfigWarning(
                    path: "\(path).open",
                    message: "\(problem); matching links will open in \"\(config.defaultApp)\""
                ))
                continue
            }
            guard let app = apps.resolve(rule.open) else { continue }
            if let profile = rule.profile, case let .failure(error) = profiles.resolve(profile, for: app) {
                warnings.append(ConfigWarning(path: "\(path).profile", message: error.description))
            }
        }
        return warnings
    }

    private static let ruleKeys: Set<String> = [
        "host", "path", "url", "regex", "opener", "open", "profile", "scheme", "strip_tracking",
    ]

    private static func parseRules(_ root: TOMLTable) throws(ConfigError) -> [Rule] {
        guard root.contains(key: "rules") else { return [] }
        let array: TOMLArray
        do {
            array = try root.array(forKey: "rules")
        } catch {
            throw ConfigError(.invalid, "must be an array of tables; write each rule as [[rules]]", path: "rules")
        }

        var rules: [Rule] = []
        for index in 0 ..< array.count {
            let number = index + 1
            let path = "rules[\(number)]"
            let table: TOMLTable
            do {
                table = try array.table(atIndex: index)
            } catch {
                throw ConfigError(.invalid, "each rule must be a table; write it as [[rules]]", path: path)
            }
            try rules.append(parseRule(TableReader(table: table, path: path), number: number))
        }
        return rules
    }

    private static func parseRule(_ reader: TableReader, number: Int) throws(ConfigError) -> Rule {
        try reader.rejectUnknownKeys(allowed: ruleKeys)

        let host = try reader.strings("host") ?? []
        for value in host where value.contains(where: { "/:*?# ".contains($0) }) {
            throw ConfigError(
                .invalid,
                "\"\(value)\" isn't a bare host name (it already matches subdomains; use url or path for more)",
                path: reader.keyPath("host")
            )
        }
        for value in host where value.hasPrefix(".") || value.hasSuffix(".") {
            throw ConfigError(
                .invalid,
                "\"\(value)\" can't start or end with \".\"; write the domain alone, e.g. \"github.com\"",
                path: reader.keyPath("host")
            )
        }

        var regex: [RegexPattern] = []
        for source in try reader.strings("regex") ?? [] {
            do {
                try regex.append(RegexPattern(source))
            } catch {
                throw ConfigError(.invalid, "invalid regular expression \"\(source)\"", path: reader.keyPath("regex"))
            }
        }

        let rule = try Rule(
            number: number,
            host: host,
            path: reader.strings("path") ?? [],
            url: reader.strings("url") ?? [],
            regex: regex,
            opener: reader.strings("opener") ?? [],
            open: reader.string("open") ?? "",
            profile: reader.string("profile"),
            scheme: reader.string("scheme"),
            stripTracking: reader.bool("strip_tracking")
        )

        if [rule.host, rule.path, rule.url, rule.opener].allSatisfy(\.isEmpty), rule.regex.isEmpty {
            throw ConfigError(
                .invalid,
                "needs at least one of host, path, url, regex or opener",
                path: reader.path
            )
        }
        if rule.open.isEmpty {
            throw ConfigError(.invalid, "missing; set it to an app name or bundle ID", path: reader.keyPath("open"))
        }
        if let scheme = rule.scheme, scheme.wholeMatch(of: /[A-Za-z][A-Za-z0-9+.\-]*/) == nil {
            throw ConfigError(
                .invalid,
                "\"\(scheme)\" isn't a URL scheme; write just the name, e.g. \"linear\"",
                path: reader.keyPath("scheme")
            )
        }
        return rule
    }
}

/// Typed access to a TOML table that reports failures with config key paths.
private struct TableReader {
    let table: TOMLTable
    let path: String

    func keyPath(_ key: String) -> String {
        path.isEmpty ? key : "\(path).\(key)"
    }

    func rejectUnknownKeys(allowed: Set<String>) throws(ConfigError) {
        for key in table.keys.sorted() where !allowed.contains(key) {
            let hint = allowed.min { editDistance($0, key) < editDistance($1, key) }
                .flatMap { editDistance($0, key) <= 2 ? " (did you mean \"\($0)\"?)" : nil } ?? ""
            throw ConfigError(.invalid, "unknown key\(hint)", path: keyPath(key))
        }
    }

    /// Every string in the config names something, so empty strings are rejected.
    func string(_ key: String) throws(ConfigError) -> String? {
        guard table.contains(key: key) else { return nil }
        let value: String
        do {
            value = try table.string(forKey: key)
        } catch {
            throw ConfigError(.invalid, "expected a string", line: error.split.line, path: keyPath(key))
        }
        try rejectEmpty([value], key)
        return value
    }

    func bool(_ key: String) throws(ConfigError) -> Bool? {
        guard table.contains(key: key) else { return nil }
        do {
            return try table.bool(forKey: key)
        } catch {
            throw ConfigError(.invalid, "expected true or false", line: error.split.line, path: keyPath(key))
        }
    }

    /// Accepts either a single string or an array of strings.
    func strings(_ key: String) throws(ConfigError) -> [String]? {
        guard table.contains(key: key) else { return nil }
        if let single = try? table.string(forKey: key) {
            try rejectEmpty([single], key)
            return [single]
        }
        let mismatch = ConfigError(.invalid, "expected a string or a list of strings", path: keyPath(key))
        guard let array = try? table.array(forKey: key) else { throw mismatch }
        var values: [String] = []
        for index in 0 ..< array.count {
            do {
                try values.append(array.string(atIndex: index))
            } catch {
                throw ConfigError(mismatch.kind, mismatch.message, line: error.split.line, path: mismatch.path)
            }
        }
        try rejectEmpty(values, key)
        return values
    }

    private func rejectEmpty(_ values: [String], _ key: String) throws(ConfigError) {
        if values.contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            throw ConfigError(.invalid, "can't be empty", path: keyPath(key))
        }
    }
}

private extension TOMLError {
    /// TOMLDecoder embeds line numbers only in its description, formatted as "(Line N) message".
    var split: (line: Int?, message: String) {
        let text = description
        guard let match = text.firstMatch(of: #/^\(Line (\d+)\) /#) else { return (nil, text) }
        return (Int(match.1), String(text[match.range.upperBound...]))
    }
}

private func editDistance(_ lhs: String, _ rhs: String) -> Int {
    let lhs = Array(lhs)
    let rhs = Array(rhs)
    var previous = Array(0 ... rhs.count)
    for (i, left) in lhs.enumerated() {
        var current = [i + 1]
        for (j, right) in rhs.enumerated() {
            current.append(min(previous[j + 1] + 1, current[j] + 1, previous[j] + (left == right ? 0 : 1)))
        }
        previous = current
    }
    return previous[rhs.count]
}
