import Foundation

/// A validated Brouter configuration.
public struct Config: Sendable {
    /// App name or bundle ID used when no rule matches, or when a rule's target can't be found.
    public var defaultApp: String
    public var stripTracking: Bool
    /// Extra query parameters (globs) stripped alongside the built-in tracking list.
    public var stripParams: [String]
    public var hideIcon: Bool
    public var rules: [Rule]

    public init(
        defaultApp: String,
        stripTracking: Bool = true,
        stripParams: [String] = [],
        hideIcon: Bool = false,
        rules: [Rule] = []
    ) {
        self.defaultApp = defaultApp
        self.stripTracking = stripTracking
        self.stripParams = stripParams
        self.hideIcon = hideIcon
        self.rules = rules
    }
}

/// One `[[rules]]` entry. Values within a match key are OR'd; distinct match keys are AND'd.
public struct Rule: Sendable {
    /// 1-based position in the config file, as shown to users.
    public var number: Int
    public var host: [String]
    public var path: [String]
    public var url: [String]
    public var regex: [RegexPattern]
    public var opener: [String]
    public var open: String
    public var profile: String?
    public var scheme: String?
    public var container: String?
    public var stripTracking: Bool?

    public init(
        number: Int,
        host: [String] = [],
        path: [String] = [],
        url: [String] = [],
        regex: [RegexPattern] = [],
        opener: [String] = [],
        open: String,
        profile: String? = nil,
        scheme: String? = nil,
        container: String? = nil,
        stripTracking: Bool? = nil
    ) {
        self.number = number
        self.host = host
        self.path = path
        self.url = url
        self.regex = regex
        self.opener = opener
        self.open = open
        self.profile = profile
        self.scheme = scheme
        self.container = container
        self.stripTracking = stripTracking
    }
}

/// A regular expression compiled at load time so invalid patterns surface as config errors.
public struct RegexPattern: Sendable {
    public let source: String
    let regex: NSRegularExpression

    public init(_ source: String) throws {
        self.source = source
        regex = try NSRegularExpression(pattern: source)
    }

    func matches(_ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
