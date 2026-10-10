# Brouter

A small, lightweight link router for macOS 14 and later. Brouter
sets itself as your default browser and lives in the menu bar. It sends each link you click to a browser, a
browser profile, or a native app, based on rules in `~/.config/brouter/config.toml`.

- Pure AppKit, with no SwiftUI, timers, or polling. It does nothing while idle.
- Config changes apply as soon as you save. A broken config never stops links from opening.
- Tracking parameters (`utm_*`, `fbclid`, `gclid`, …) are removed by default.
- A read-only CLI shows exactly why a link would go where it goes.

## Install

You need Xcode and [mise](https://mise.jdx.dev).

```sh
mise install          # pins xcodegen, swiftlint, swiftformat
mise run build        # generates Brouter.xcodeproj, builds Release into build/
cp -R build/Build/Products/Release/Brouter.app /Applications/
open /Applications/Brouter.app
```

| Task | What it does |
|---|---|
| `mise run gen` | Generates `Brouter.xcodeproj` from `project.yml` |
| `mise run build` | Runs `gen`, then builds Release into `build/` |
| `mise run run` | Builds and launches the app |
| `mise run lint` | Runs SwiftLint (strict) and checks SwiftFormat |
| `mise run fmt` | Formats the sources |
| `mise run release` | Tags the next CalVer version (`vYYYY.M.N`) and pushes it. CI builds the app and attaches a `.dmg` and `.zip` to a GitHub release |

On first launch, Brouter:

1. Records your current default browser.
2. Writes a commented starter config that uses that browser as `default`.
3. Asks macOS to make Brouter the default browser.
4. Opens the config in your editor.

Launch at Login works only when the app is in `/Applications`.

## Config reference

```toml
default = "Firefox"            # required
strip_tracking = true
strip_params = ["ref", "mkt_*"]
hide_icon = false

[[rules]]
host = ["github.com", "atlassian.net"]
open = "Google Chrome"
profile = "Work"

[[rules]]
host = "linear.app"
open = "Linear"
scheme = "linear"
```

Anywhere an app is expected, you can use its Finder name (`Google Chrome`) or its bundle ID
(`com.google.Chrome`). Unknown keys and empty strings are errors, so a typo is caught rather than ignored.

### Global keys

| Key | Default | Meaning |
|---|---|---|
| `default` | (required) | App for links that no rule matches, and the fallback for missing apps |
| `strip_tracking` | `true` | Remove tracking query parameters from every link |
| `strip_params` | `[]` | Extra parameters to remove, on top of the built-in list (globs, case-insensitive) |
| `hide_icon` | `false` | Hide the menu bar icon. It reappears while the config has an error or warning |

### Rule keys

Each `[[rules]]` entry needs at least one match key and an `open`. A match key accepts a string or a list of
strings.

| Key | Kind | Meaning |
|---|---|---|
| `host` | match | Domain. Also matches its subdomains. Case-insensitive |
| `path` | match | Glob on the URL path |
| `url` | match | Glob on the whole URL |
| `regex` | match | Regular expression searched anywhere in the whole URL |
| `opener` | match | App the link was clicked in, by any name `open` accepts or by bundle ID. Case-insensitive |
| `open` | action | App to open the link in (required) |
| `profile` | action | Browser profile, by display name (see [Profiles](#profiles)) |
| `container` | action | Firefox or Zen container, by display name (see [Containers](#containers)) |
| `scheme` | action | Replace the URL scheme, e.g. `"linear"` (see [Native apps](#native-apps)) |
| `strip_tracking` | action | Override the global `strip_tracking` for this rule |

### Matching

- Rules are checked top to bottom. The first match wins. If nothing matches, the link opens in `default`.
- Matching combines keys like this:
  - Within a key, any one value may match (OR).
  - Across keys, every key the rule lists must match (AND).
- `host = "github.com"` matches `github.com` and `gist.github.com`, but not `notgithub.com`. Write only the bare
  host: no scheme, path, port, `*`, or leading or trailing `.`.
- `path` and `url` globs match the whole string and are case-sensitive.
  - `*` matches any run of characters, including `/`.
  - Every other character is literal.
  - Paths are matched percent-encoded, and an empty path counts as `/`. Use `path = "/team/*"`, not
    `path = "team"`.
- `regex` is searched anywhere in the URL. Anchor it with `^…$` to match the whole URL. TOML basic strings need
  doubled backslashes (`"\\.pdf$"`), or use a literal string (`'\.pdf$'`).
- `opener` compares the clicking app's Finder name, bundle name, display name, or bundle ID, the same names `open`
  accepts. For example, `opener = "Code"` matches Visual Studio Code. When a link comes from a command-line tool
  such as `open` in Terminal, the opener is the frontmost app.
- Matching always uses the original link. Tracking removal and scheme swaps happen after a rule is chosen.

### Tracking parameters

Brouter strips these by default: `utm_*`, `fbclid`, `igshid`, `gclid`, `dclid`, `gbraid`, `wbraid`, `msclkid`,
`yclid`, `twclid`, `ttclid`, `li_fat_id`, `mc_eid`, `mc_cid`, `_hsenc`, `_hsmi`, `oly_enc_id`, `oly_anon_id`,
`vero_id`, `rb_clickid`, `s_cid`, `si`.

- `strip_params` adds to that list. Its entries are globs and are case-insensitive.
- `strip_tracking = false` turns off both the built-in list and `strip_params`.
- A rule's own `strip_tracking` overrides the global setting for links that rule matches.

### Fallback

If a rule's `open` app isn't installed, the link opens in `default` instead, without that rule's `scheme` swap,
`container`, or `profile`. A rule or `default` that names Brouter itself is treated the same way as a missing app. `brouter check`
lists both as warnings. If `default` can't be used either, the link opens in Safari. If an app fails to open a
link, Brouter retries in Safari, without any scheme swap or container.

### Profiles

| Browser | Profile support | How the profile is selected |
|---|---|---|
| Chrome, Brave, Edge, Vivaldi, Chromium | Yes | Display name from the browser's `Local State`, passed as `--profile-directory=<dir>` |
| Firefox, Zen | Yes | Display name from `profiles.ini`, passed as `-P <name>` |
| Safari, Arc | No | Neither browser accepts a profile at launch |

- You can also give the raw profile directory name, e.g. `Profile 1`.
- A profile that can't be found produces a warning, and the link opens without one.
- If Firefox is already running, `-P` may show the profile manager instead of opening the link.

### Containers

`container` opens the link in a Firefox container by wrapping it as `ext+container:name=<name>&url=<link>`.

- Firefox and Zen only, with the [Open external links in a container](https://addons.mozilla.org/firefox/addon/open-url-in-container/) extension installed.
- `name` is the container's display name.
- Can't be combined with `scheme`. Combines with `profile`.
- Skipped on fallback, and for other browsers, with a warning in `brouter check`.

## Native apps

`scheme` replaces only the scheme and keeps the host, path, query, and fragment. For example,
`https://linear.app/acme/issue/ABC-1` becomes `linear://linear.app/acme/issue/ABC-1`. That works only for apps
that accept their web URL under their own scheme. Many apps don't.

| App | Recipe | Status |
|---|---|---|
| Linear | `host = "linear.app"`, `open = "Linear"`, `scheme = "linear"` | Works. Linear documents the `linear://linear.app/…` form |
| Notion | `host = "notion.so"`, `open = "Notion"`, `scheme = "notion"` | Works. Notion documents swapping `https` for `notion`. Public `*.notion.site` pages aren't covered |
| Figma | `host = "figma.com"`, `path = ["/file/*", "/design/*", "/proto/*"]`, `open = "Figma"`, `scheme = "figma"` | Community-confirmed for `/file/` links. `/design/` and `/proto/` aren't verified. Figma's own "Open links in desktop app" setting is an alternative |
| Zoom | None. Leave Zoom links to your browser | A swap gives `zoommtg://zoom.us/j/123?pwd=…`, but the app expects `zoommtg://zoom.us/join?confno=123&pwd=…`. Zoom's web page already hands off to the app |
| Slack | None. Leave Slack links to your browser | Slack deep links are ID-based (`slack://channel?team=T…&id=C…`) and don't accept web paths. Slack's web page offers to open the app |
| Spotify | Try `host = "open.spotify.com"`, `open = "Spotify"`, with no `scheme` | Spotify uses `spotify:track:<id>` URIs, which a swap can't produce. The Spotify app handling a plain `https` link is reported by the community but not verified |

Rewrites that need more than a scheme swap, such as Zoom's or Slack's, aren't supported.

## Command line

The CLI is read-only. It never opens links or launches apps.

```sh
alias brouter=/Applications/Brouter.app/Contents/MacOS/Brouter

brouter test https://gist.github.com/x --opener Slack   # explain where a link would go
brouter test "https://ex.com/?utm_source=a" --json     # same, as JSON
brouter check                                          # validate the config, list warnings
brouter --config ./other.toml check                    # use a different config file
```

`test` prints each rule it evaluated, with ✓ or ✗ per key and the reason for each failure. It then prints the
rewrites, the chosen app and profile, and the final URL. `--opener` takes an app name or bundle ID.

Exit codes: `0` ok, `1` config error, `2` usage error.

## Menu

| Item | What it does |
|---|---|
| Status line | Shows `Config OK · N rules`, or the error with its line or key, or the warning count with details |
| Open Config | Opens the config in the app registered for `.toml` files, or TextEdit. Recreates the starter config if the file is missing |
| Reveal Config in Finder | Shows the config file in Finder |
| Reload Config | Reloads the config. Rarely needed, since saving reloads automatically |
| Recent Links | The last 10 links, shown as `host → App (rule N)`, `(default)` or `(fallback)`. Click one to copy its URL |
| Set as Default Browser | Shown only when Brouter isn't the default |
| Launch at Login | Toggles the login item. Opens System Settings if macOS needs your approval |
| Quit Brouter | Quits the app |

The icon switches to ⚠︎ while the config has an error or warnings. With `hide_icon = true`, reopen Brouter from
Finder or Spotlight to show the icon until the next config change.

## Config errors

- Syntax errors show the line number. Other errors show the key, e.g. `rules[3].regex`.
- While the file has an error, Brouter keeps routing with the last config that loaded successfully.
- If no config has loaded since launch, every link opens in Safari, unchanged.
- Warnings, such as an app that isn't installed or an unknown profile, don't stop routing.
- Fixing and saving the file clears the error. You don't need to reload.

## Privacy

Brouter makes no network requests and sends no analytics. Recent Links are kept in memory only and are cleared
when Brouter quits.

## License

MIT
