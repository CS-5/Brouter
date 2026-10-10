import Foundation

/// Where a link goes and why.
public struct Decision: Codable, Sendable, Equatable {
    /// The link as received.
    public var input: URL
    /// The link to open, after rewrites.
    public var url: URL
    public var opener: Opener?
    /// Number of the matching rule, or nil when the default app handles the link.
    public var rule: Int?
    /// The `open` value of the matching rule, or the configured default.
    public var target: String
    /// The app to open the link in; nil only when even the default app can't be found.
    public var app: ResolvedApp?
    public var profile: String?
    /// Launch arguments that select `profile`.
    public var arguments: [String]
    /// True when the matching rule's app couldn't be found and the default app was used instead.
    public var fallback: Bool
    public var stripTracking: Bool
    public var rewrites: [Rewrite]
    /// Every rule evaluated, in order, up to and including the match.
    public var trace: [RuleTrace]
    public var notes: [String]
}

public struct Router: Sendable {
    public let config: Config
    let apps: any AppResolving
    let profiles: ProfileResolver

    public init(config: Config, apps: any AppResolving, profiles: ProfileResolver = ProfileResolver()) {
        self.config = config
        self.apps = apps
        self.profiles = profiles
    }

    public func route(_ input: URL, opener: Opener? = nil) -> Decision {
        var trace: [RuleTrace] = []
        var matched: Rule?
        for rule in config.rules {
            let result = Matcher.evaluate(rule, url: input, opener: opener)
            trace.append(result)
            if result.matched {
                matched = rule
                break
            }
        }

        var notes: [String] = []
        let target = matched?.open ?? config.defaultApp
        var app = resolve(target, notes: &notes)
        var fallback = false
        if app == nil, matched != nil {
            fallback = true
            app = resolve(config.defaultApp, notes: &notes)
            if app != nil {
                notes.append("fell back to default \"\(config.defaultApp)\"")
            }
        }
        if app == nil {
            notes.append("no usable app; the link opens in Safari")
        }

        let stripTracking = matched?.stripTracking ?? config.stripTracking
        var (url, rewrites) = rewrite(
            input, rule: matched, stripTracking: stripTracking, fallback: fallback, notes: &notes
        )
        let (wrapped, changes) = containerRewrite(url, rule: matched, app: app, fallback: fallback, notes: &notes)
        (url, rewrites) = (wrapped, rewrites + changes)

        var profile: String?
        var arguments: [String] = []
        if let requested = matched?.profile {
            if fallback {
                notes.append("profile \"\(requested)\" skipped because \"\(target)\" can't be used")
            } else if let app {
                switch profiles.resolve(requested, for: app) {
                case let .success(args):
                    profile = requested
                    arguments = args
                case let .failure(error):
                    notes.append("\(error); opened without a profile")
                }
            }
        }

        return Decision(
            input: input,
            url: url,
            opener: opener,
            rule: matched?.number,
            target: target,
            app: app,
            profile: profile,
            arguments: arguments,
            fallback: fallback,
            stripTracking: stripTracking,
            rewrites: rewrites,
            trace: trace,
            notes: notes
        )
    }

    /// Resolves an app, treating the router itself like a missing app.
    private func resolve(_ target: String, notes: inout [String]) -> ResolvedApp? {
        guard let app = apps.resolve(target) else {
            notes.append("\"\(target)\" not found")
            return nil
        }
        guard !apps.isSelf(app) else {
            notes.append("\"\(target)\" is Brouter itself")
            return nil
        }
        return app
    }

    private func rewrite(
        _ input: URL,
        rule: Rule?,
        stripTracking: Bool,
        fallback: Bool,
        notes: inout [String]
    ) -> (URL, [Rewrite]) {
        var url = input
        var rewrites: [Rewrite] = []
        if stripTracking {
            let (stripped, changes) = Rewriter.strip(url, patterns: TrackingParams.builtIn + config.stripParams)
            url = stripped
            rewrites += changes
        }
        if let rule, let scheme = rule.scheme {
            if fallback {
                notes.append("scheme swap to \"\(scheme)\" skipped because \"\(rule.open)\" can't be used")
            } else {
                let (swapped, changes) = Rewriter.swapScheme(url, to: scheme)
                url = swapped
                rewrites += changes
            }
        }
        return (url, rewrites)
    }

    private func containerRewrite(
        _ url: URL,
        rule: Rule?,
        app: ResolvedApp?,
        fallback: Bool,
        notes: inout [String]
    ) -> (URL, [Rewrite]) {
        guard let rule, let container = rule.container else { return (url, []) }
        if fallback {
            notes.append("container \"\(container)\" skipped because \"\(rule.open)\" can't be used")
        } else if let app {
            if profiles.supportsContainers(bundleID: app.bundleID ?? "") {
                return Rewriter.wrapInContainer(url, name: container)
            }
            notes.append("containers aren't supported for \"\(app.name)\"; opened without a container")
        }
        return (url, [])
    }
}
