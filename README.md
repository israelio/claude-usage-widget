# Claude Usage Widget

A native macOS menu bar app (plus desktop widgets) that shows your **Claude Code usage** at a glance: 5-hour session, weekly limit, pace, 90-day token and cost history, and smart notifications.

> ⭐ **Staraware.** Instead of paying, pay with a star. If you like it, [star the repo](https://github.com/israelio/claude-usage-widget). Made by Ohad Israeli.

## Screenshot

<p align="center">
  <img src="docs/images/popover.png" alt="Claude Usage popover showing session, weekly and Fable limits, pace chart, daily usage and token costs" width="360">
</p>

## Features

Top to bottom, the panel shows:

- **5-Hour Session / Weekly Limit / Weekly Fable** — percent used, a progress bar, and when the window resets (countdown plus clock time). The green/red `▼9%` / `▲9%` next to the percent is how far you are below/above a perfectly even burn rate for that window. The label on the right says **On track**, **Ahead of pace** or **Will exceed**, based on where your current rate would land at reset. The third card is the per-model weekly window (Fable, when your plan has one).
- **Pace** — a chart of your pace over the current 5-hour window. Above the 0% line means you are using it faster than evenly; below means slower. It fills in as the app collects samples.
- **Daily Usage** — cost per day with a **7d / 30d / 90d** switch.
- **Token Usage** — input, output and cache tokens plus cost for Today, Last 7 Days, This Month and Last 30 Days, then each model's share of your last 30 days of spend. Costs are API-equivalent estimates from an editable price table, not your subscription bill.
- **Next refresh** — countdown to the next poll. If the live endpoint is unreachable it shows "updated Xm ago" or an "estimated" badge instead.
- **Footer** — open Claude's usage page, refresh now, open the 90-day History window, Settings, About, and Quit.

More:

- **Menu bar** — a compact label such as `🟢 42% ▼7% · 71%` (colour shows how close you are to the limit). Choose session %, session + weekly, or icon only in Settings.
- **Floating panel** — turn on *Floating always-on-top panel* in Settings to pin the same view on your desktop. It remembers its position.
- **90-day history** — a daily chart you can switch between cost and tokens, last-30-day model breakdown, totals, and **Export CSV**.
- **Smart notifications**
  - *Thresholds*: one alert per window at the highest level crossed (default 50/75/90%, editable).
  - *Burn-rate warning*: you are on course to hit the limit before it resets.
  - *Reset notice*: your window reset and usage is available again.
  - *Digests*: a daily summary and a Monday weekly summary of tokens and cost, at an hour you choose.
  - *Quiet hours*: suppress alerts overnight.
- **Desktop widgets** — small (session ring), medium (session + weekly + today's cost) and large (adds weekly Fable and a 7-day chart). They need a build signed with your Apple Team ID (see below).
- **Settings** — refresh interval, menu bar mode, notification options, fallback token budgets, and the per-model price table.
- **Offline fallback** — if the usage endpoint or Keychain is unavailable, usage is estimated from your local logs and marked as estimated. The last real values are kept and shown as stale rather than replaced.
- **Light and dark** — follows your system appearance with a glass material.

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

[MIT](LICENSE) © 2026 Ohad Israeli
