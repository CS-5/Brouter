/// The commented config written on first run; it doubles as the reference for every option.
public enum StarterConfig {
    // swiftlint:disable function_body_length
    /// - Parameters:
    ///   - browsers: Installed browsers, listed in the header so users know what names they can use.
    ///   - previousDefault: The default browser before Brouter took over; becomes `default`.
    public static func make(browsers: [ResolvedApp], previousDefault: ResolvedApp?) -> String {
        let defaultApp = previousDefault?.name ?? "Safari"
        let browserLines = browsers.isEmpty
            ? "#   (none detected)"
            : browsers.map { "#   \($0.name)\($0.bundleID.map { " (\($0))" } ?? "")" }.joined(separator: "\n")
        let profileBrowser = browsers.first { ProfileResolver.families[$0.bundleID ?? ""] != nil }?.name
            ?? "Google Chrome"

        return """
        # Brouter config
        #
        # Brouter is your default browser. Every link you click comes here first and is sent
        # to the app chosen by the rules below. Changes apply as soon as you save this file.
        #
        # Test a link without opening anything:
        #   Brouter.app/Contents/MacOS/Brouter test https://example.com --opener Slack
        #   Brouter.app/Contents/MacOS/Brouter check
        #
        # Browsers found on this Mac (use the name or the bundle ID anywhere an app is expected):
        \(browserLines)

        # App that opens every link no rule matches. Required.
        default = "\(defaultApp)"

        # Remove tracking parameters (utm_*, fbclid, gclid, msclkid, ...) from every link.
        # Rules can override this with their own strip_tracking.
        strip_tracking = true

        # More query parameters to remove, on top of the built-in list. `*` matches anything.
        # Only applies while tracking stripping is on.
        # strip_params = ["ref", "mkt_*"]

        # Hide the menu bar icon. It comes back on its own if the config has a problem.
        hide_icon = false

        # ---------------------------------------------------------------------------
        # Rules
        #
        # Rules are checked top to bottom and the first match wins. Each rule needs at
        # least one match key and an `open`.
        #
        # Match keys (each takes a string or a list; any value in a list may match,
        # and every key given must match):
        #   host   = "github.com"       domain, also matches subdomains (gist.github.com); ignores case
        #   path   = "/team/*"          glob on the path; `*` matches anything, including "/"
        #   url    = "https://x.com/*"  glob on the whole link
        #   regex  = "^https://.*\\\\.pdf$"  regular expression searched in the whole link
        #   opener = "Slack"            app the link was clicked in, by name or bundle ID; ignores case
        #
        # Actions:
        #   open           = "Firefox"  app name or bundle ID: a browser or any other app (required)
        #   profile        = "Work"     browser profile by display name (Chrome, Brave, Edge,
        #                               Vivaldi, Chromium, Firefox, Zen)
        #   scheme         = "linear"   swap the link's scheme to open it in a native app:
        #                               https://linear.app/x becomes linear://linear.app/x
        #   strip_tracking = false      override the global tracking setting for this rule
        #
        # Rules match the original link; tracking removal and scheme swaps happen afterwards.
        # If a rule's app isn't installed, the link opens in `default` instead.
        # ---------------------------------------------------------------------------

        # Work links in a dedicated browser profile:
        # [[rules]]
        # host = ["github.com", "atlassian.net"]
        # open = "\(profileBrowser)"
        # profile = "Work"

        # Links clicked in Slack open in a specific browser:
        # [[rules]]
        # opener = "Slack"
        # open = "\(defaultApp)"

        # Open Linear links in the Linear app:
        # [[rules]]
        # host = "linear.app"
        # open = "Linear"
        # scheme = "linear"

        # Keep tracking parameters for one site:
        # [[rules]]
        # host = "example.com"
        # path = "/campaigns/*"
        # open = "\(defaultApp)"
        # strip_tracking = false

        """
    }
    // swiftlint:enable function_body_length
}
