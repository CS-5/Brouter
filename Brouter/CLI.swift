import BrouterCore
import Foundation

/// Read-only command line interface: explains routing decisions without opening links or launching apps.
enum CLI {
    enum Status {
        static let ok: Int32 = 0
        static let configError: Int32 = 1
        static let usage: Int32 = 2
    }

    static let usage = """
    usage: Brouter [--config <path>] <command>

    commands:
      test <url> [--opener <name|bundle ID>] [--json]   explain where a link would open, without opening it
      check [--json]                                    validate the config and report warnings
      help                                              show this help

    options:
      --config <path>   config file to use (default: ~/.config/brouter/config.toml)

    exit status: 0 ok, 1 config error, 2 usage error
    """

    private static let commands: Set = ["test", "check", "help"]

    /// Runs the CLI when `arguments` name a command or start with an option and returns its exit status;
    /// returns nil to launch the app. macOS can pass `-NS…`, `-Apple…` and `-psn_…` arguments to GUI launches,
    /// so those still launch the app.
    static func runIfRequested(_ arguments: [String]) -> Int32? {
        let args = Array(arguments.dropFirst())
        guard let first = args.first else { return nil }
        let isLaunchArgument = ["-NS", "-Apple", "-psn_"].contains { first.hasPrefix($0) }
        guard commands.contains(first) || (first.hasPrefix("-") && !isLaunchArgument) else { return nil }
        return run(args)
    }

    private struct UsageError: Error {
        var message: String
        init(_ message: String) {
            self.message = message
        }
    }

    private struct Invocation {
        var command: String?
        var positionals: [String] = []
        var configPath: String?
        var opener: String?
        var json = false
        var help = false
    }

    private static func run(_ args: [String]) -> Int32 {
        let invocation: Invocation
        switch parse(args) {
        case let .success(parsed): invocation = parsed
        case let .failure(error): return usageError(error.message)
        }
        let configURL = invocation.configPath.map { URL(filePath: NSString(string: $0).expandingTildeInPath) }
            ?? ConfigLoader.defaultURL

        if invocation.help {
            print(usage)
            return Status.ok
        }
        switch invocation.command {
        case "test":
            guard invocation.positionals.count == 1 else { return usageError("test takes exactly one URL") }
            return test(invocation.positionals[0], opener: invocation.opener, json: invocation.json, config: configURL)
        case "check":
            guard invocation.positionals.isEmpty, invocation.opener == nil else {
                return usageError("check takes no arguments")
            }
            return check(json: invocation.json, config: configURL)
        case "help":
            print(usage)
            return Status.ok
        default:
            return usageError(invocation.command.map { "unknown command \($0)" })
        }
    }

    private static func parse(_ args: [String]) -> Result<Invocation, UsageError> {
        var invocation = Invocation()
        var iterator = args.makeIterator()
        while let arg = iterator.next() {
            switch arg {
            case "--config", "--opener":
                guard let value = iterator.next() else { return .failure(UsageError("\(arg) needs a value")) }
                if arg == "--config" {
                    invocation.configPath = value
                } else {
                    invocation.opener = value
                }
            case "--json":
                invocation.json = true
            case "--help", "-h":
                invocation.help = true
            case _ where arg.hasPrefix("-") && arg.count > 1:
                return .failure(UsageError("unknown option \(arg)"))
            case _ where invocation.command == nil:
                invocation.command = arg
            default:
                invocation.positionals.append(arg)
            }
        }
        return .success(invocation)
    }

    private static func test(_ link: String, opener: String?, json: Bool, config configURL: URL) -> Int32 {
        guard let url = URL(string: link), url.scheme != nil else {
            return usageError("\"\(link)\" isn't a URL; include the scheme, e.g. https://")
        }
        let config: Config
        do {
            config = try ConfigLoader.load(from: configURL)
        } catch {
            return report(error, json: json, config: configURL)
        }

        let resolver = WorkspaceAppResolver()
        let decision = Router(config: config, apps: resolver).route(url, opener: opener.map(resolveOpener))
        if json {
            writeJSON(decision)
        } else {
            print(decision.explanation)
        }
        return Status.ok
    }

    private struct CheckReport: Encodable {
        var ok: Bool
        var config: String
        var rules: Int?
        var error: ConfigError?
        var warnings: [ConfigWarning]
    }

    private static func check(json: Bool, config configURL: URL) -> Int32 {
        let config: Config
        do {
            config = try ConfigLoader.load(from: configURL)
        } catch {
            return report(error, json: json, config: configURL)
        }

        let warnings = ConfigLoader.warnings(for: config, apps: WorkspaceAppResolver())
        let path = configURL.path(percentEncoded: false)
        if json {
            writeJSON(CheckReport(ok: true, config: path, rules: config.rules.count, warnings: warnings))
        } else {
            print("✓ \(path): \(config.rules.count) rule\(config.rules.count == 1 ? "" : "s")")
            for warning in warnings {
                print("warning: \(warning)")
            }
        }
        return Status.ok
    }

    private static func report(_ error: ConfigError, json: Bool, config configURL: URL) -> Int32 {
        let path = configURL.path(percentEncoded: false)
        if json {
            writeJSON(CheckReport(ok: false, config: path, error: error, warnings: []))
        } else {
            writeError("✗ \(path)\nerror: \(error)")
        }
        return Status.configError
    }

    /// Resolves an installed app so rules can match either its name or bundle ID, as they would for a real click.
    private static func resolveOpener(_ value: String) -> Opener {
        if let opener = WorkspaceAppResolver().resolve(value).flatMap({ WorkspaceAppResolver.opener(at: $0.url) }) {
            return opener
        }
        let looksLikeBundleID = value.contains(".") && !value.contains(" ")
        return looksLikeBundleID ? Opener(name: nil, bundleID: value) : Opener(name: value, bundleID: nil)
    }

    private static func usageError(_ message: String? = nil) -> Int32 {
        writeError((message.map { "error: \($0)\n\n" } ?? "") + usage)
        return Status.usage
    }

    private static func writeError(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }

    private static func writeJSON(_ value: some Encodable) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return }
        FileHandle.standardOutput.write(data + Data("\n".utf8))
    }
}
