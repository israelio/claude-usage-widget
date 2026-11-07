# Claude Usage Widget

A native macOS menu bar app (plus desktop widgets) that shows your **Claude Code usage** at a glance: 5-hour session, weekly limit, pace, 90-day token and cost history, and smart notifications.

> ⭐ **Staraware.** Instead of paying, pay with a star. If you like it, [star the repo](https://github.com/israelio/claude-usage-widget). Made by Ohad Israeli.

## Features

- **Live limits** — 5-hour session, weekly limit and per-model weekly limit (e.g. Fable), with reset countdowns and an "On track / Ahead / Will exceed" pace indicator.
- **Menu bar** — compact `🟢 42% ▼7% · 71%` label; modes: session %, session + weekly, or icon only.
- **Glass popover** — follows your system light/dark theme. Optional always-on-top floating panel.
- **Token + cost breakdown** — today / 7 days / month / 30 days, input / output / cache, per-model share.
- **90-day history** — daily chart (tokens or cost) and CSV export.
- **Smart notifications** — threshold crossings (default 50/75/90%), burn-rate warning, window reset notice, daily and weekly digests, quiet hours.
- **Desktop widgets** — small, medium and large (WidgetKit).
- **Offline fallback** — if the usage endpoint or Keychain is unavailable, usage is estimated from local logs and clearly marked as estimated.

## Requirements

- macOS 14 or later
- Claude Code installed and signed in (the app reads its login from the Keychain and its logs from `~/.claude/projects`)
- To build: Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Install

Download the latest DMG from [Releases](https://github.com/israelio/claude-usage-widget/releases) and drag **Claude Usage** to Applications.

Release DMGs are ad-hoc signed and not notarized. On first launch right-click the app and choose **Open**, or run:

```sh
xattr -dr com.apple.quarantine "/Applications/Claude Usage.app"
```

On first launch macOS asks for access to the "Claude Code-credentials" Keychain item. Choose **Always Allow**.

Desktop widgets need a build signed with your own Apple Team ID, so build from source for those (below).

## Build from source

```sh
git clone https://github.com/israelio/claude-usage-widget.git
cd claude-usage-widget
cp Local.xcconfig.example Local.xcconfig   # then edit it (see below)
xcodegen generate
open ClaudeUsageWidget.xcodeproj           # run the ClaudeUsageWidget scheme
```

`Local.xcconfig` holds your signing settings and is **gitignored** (never commit it):

```
DEVELOPMENT_TEAM = ABCDE12345
APP_GROUP_ID = ABCDE12345.com.ohad.claudeusagewidget
```

- Find your Team ID at developer.apple.com/account → Membership details.
- The App Group is how the app shares data with the widgets. On macOS 15+ it should be prefixed with your Team ID.

Unsigned build (menu bar app only, no widgets):

```sh
xcodebuild -project ClaudeUsageWidget.xcodeproj -scheme ClaudeUsageWidget \
  -configuration Debug -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" build
```

## How it works

| Piece | Source |
|---|---|
| 5h / weekly limits and resets | Claude's usage endpoint, authenticated with the Claude Code OAuth token from the Keychain |
| Tokens and history | Incremental parse of `~/.claude/projects/**/*.jsonl`, deduplicated by message id |
| Cost | Editable per-model price table (Settings) |
| Fallback | Local token estimate vs. budgets you configure in Settings |

Code layout:

- `Packages/UsageCore` — parsing, pricing, history, pace, alerts, limits client (unit tested)
- `App/` — SwiftUI menu bar app, popover, floating panel, settings, history
- `Widget/` — WidgetKit extension
- `project.yml` — XcodeGen project definition
- `scripts/make-dmg.sh` — builds a DMG

Run the tests:

```sh
swift test --package-path Packages/UsageCore
```

## Notes and limitations

- **Costs are API-equivalent estimates**, not what a subscription plan bills. Check the default prices in Settings; they may lag current Anthropic pricing.
- The usage endpoint is **undocumented** and may change. That is why the local fallback exists.
- Tokens are only read from the Keychain and sent to Anthropic's API; they are never logged or stored.

## License

No license file yet; add one (e.g. MIT) before accepting contributions.
