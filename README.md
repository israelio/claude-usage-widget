<p align="center"><img src="docs/images/icon.png" width="128" alt="Claude Usage icon"></p>

# Claude Usage Widget

A native macOS menu bar app (plus desktop widgets) that shows your **Claude Code usage** at a glance: 5-hour session, weekly limit, pace, a 90-day usage window (by project and by model), and smart notifications.

**[⬇️ Download the latest release](https://github.com/israelio/claude-usage-widget/releases/latest)** · [All releases](https://github.com/israelio/claude-usage-widget/releases)

> ⭐ **Staraware.** Instead of paying, pay with a star. If you like it, [star the repo](https://github.com/israelio/claude-usage-widget). Made by Ohad Israeli.

## Screenshots

<table>
  <tr>
    <td valign="top" align="center">
      <img src="docs/images/popover.png" alt="Claude Usage panel: session, weekly and Fable limits with pace markers, pace chart, daily usage, token costs and plan" width="300"><br>
      <sub><b>The panel</b>: limits, pace, daily usage, tokens and plan</sub>
    </td>
    <td valign="top" align="center">
      <img src="docs/images/widgets-color.png" alt="Claude Usage desktop widgets in full-color style" width="235">
      &nbsp;
      <img src="docs/images/widgets-mono.png" alt="Claude Usage desktop widgets in monochrome style" width="235"><br>
      <sub><b>Desktop widgets</b>: full-color (left) and the monochrome macOS default (right). Small, medium and large; click one to open the panel.</sub>
    </td>
  </tr>
</table>

<table>
  <tr>
    <td valign="top" align="center" width="33%">
      <a href="docs/images/usage-projects.png"><img src="docs/images/usage-projects.png" alt="Usage window grouped by project: 90-day daily chart on top, projects ranked by cost with share bars, and an expanded project showing its model split and a daily cost chart" width="290"></a><br>
      <sub><b>Usage, by project</b>: each project expands to its model split and daily trend</sub>
    </td>
    <td valign="top" align="center" width="33%">
      <a href="docs/images/usage-models.png"><img src="docs/images/usage-models.png" alt="Usage window grouped by model: models ranked by cost, with an expanded model listing the projects that used it and a daily cost chart" width="290"></a><br>
      <sub><b>Usage, by model</b>: which projects used each model</sub>
    </td>
    <td valign="top" align="center" width="33%">
      <a href="docs/images/usage-sessions.png"><img src="docs/images/usage-sessions.png" alt="Usage window in Sessions mode: one bar per 5-hour work session over the last 7 days, with projects ranked by cost and an expanded project showing a cost-per-session chart" width="290"></a><br>
      <sub><b>Usage, by session</b>: Claude's rolling 5-hour work windows</sub>
    </td>
  </tr>
</table>

<sub>Click a Usage screenshot for the full size. Project names in them are placeholders.</sub>

Add the widgets from **Edit Widgets** on the desktop. macOS shows desktop widgets in the monochrome style unless you pick **System Settings → Desktop & Dock → Widgets → Widget style → Full-color**; the widgets are readable in both.

## Features

Top to bottom, the panel shows its title and version, then:

- **5-Hour Session / Weekly Limit / Weekly Fable** — percent used, a progress bar, and when the window resets (countdown plus clock time). The green/red `▼9%` / `▲9%` next to the percent is how far you are below/above a perfectly even burn rate for that window. The label on the right says **On track**, **Ahead of pace** or **Will exceed**, based on where your current rate would land at reset. The third card is the per-model weekly window (Fable, when your plan has one).
- **Pace** — a chart of your pace over the current 5-hour window. Above the 0% line means you are using it faster than evenly; below means slower. It fills in as the app collects samples.
- **Daily Usage** — cost per day with a **7d / 30d / 90d** switch.
- **Usage window** — click a bar on Daily Usage (or the chart button in the footer) to open one window with the 90-day daily chart on top, switchable between cost and tokens; click a bar to pick that day, or choose a day (with previous/next and a date picker) or the last 7, 30 or 90 days, and the chart highlights the range. Switch **Days | Sessions** to see Claude's rolling 5-hour work sessions instead: one bar per session (click to select it, hover for its time, cost and projects), previous/next session buttons, and ranges of 3, 7, 14 or 30 days; session detail only exists from the hourly history the app has (see What's new). Below, **Group by Project** lists which projects used the range's tokens and cost, and each project expands to its per-model breakdown and daily trend; **Group by Model** lists the models across all projects, and each model expands to the projects that used it and its daily trend. Git worktrees and sub-folders are merged into their main repository, and **Export** saves CSV: daily totals (Days) or sessions (Sessions), projects, projects by model, or models by project. History from before per-project tracking (or from logs Claude Code no longer keeps) appears as "Earlier (unknown)".
- **Token Usage** — input, output and cache tokens plus cost for Today, Last 7 Days, This Month and Last 30 Days, then each model's share of your last 30 days of spend. Costs are API-equivalent estimates from an editable price table, not your subscription bill.
- **Plan** — your plan (for example Max 5x) and subscription status, the estimated renewal date, and extra-usage spend if you have it enabled. Anthropic doesn't expose the renewal date, so it is estimated as the next monthly anniversary of your subscription start; annual plans renew on a different schedule.
- **Next refresh** — countdown to the next poll. If the live endpoint is unreachable it shows "updated Xm ago" or an "estimated" badge instead.
- **Used or left** — show usage as percent used or percent remaining (`98% left`) in the menu bar and the widgets: Settings → Display → *Show usage as*, or per widget via right-click → *Edit Widget* (*Same as app setting* / *Used* / *Left*). The small widget can also show either the 5-hour session or the weekly limit. Colours always follow how much you have used.
- **Footer** — open Claude's usage page, refresh now, open the Usage window, Settings, About, and Quit.

More:

- **Menu bar** — a compact label such as `🟢 42% ▼7% · 71%` (colour shows how close you are to the limit). Choose session %, session + weekly, or icon only in Settings, or pick exactly what to show (status dot, session, pace, weekly, per-model weekly such as Fable, today's cost, session reset countdown) under Settings → Display → Menu bar → Custom….
- **Floating panel** — turn on *Floating always-on-top panel* in Settings to pin the same view on your desktop. It remembers its position.
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

## What's new in v0.1.11

- **Sessions in the Usage window.** Claude's limits use rolling 5-hour windows that start at your first message, so the Usage window can now show those work sessions as well as days. Switch **Days | Sessions** in the top bar: the chart shows one bar per session (cost or tokens), you can step through sessions, jump to a date, or aggregate the sessions of the last 3, 7, 14 or 30 days, and the project and model tables (with an hourly or per-session trend) and a new **Sessions** CSV export follow the selection. Retention caveat: hourly detail is built once from the logs Claude Code still keeps and then accumulates, so sessions only go back as far as that; the window says so when a range reaches earlier.

## What's new in v0.1.10

- **One Usage window.** Click a bar on the Daily Usage chart, or use the footer button, to open a single window with the 90-day chart (cost or tokens, bars in the chosen range highlighted, click a bar to pick that day). Pick a date, step to the previous or next day, or widen to 7, 30 or 90 days, then group by project (expand a project for a per-model breakdown) or by model (expand a model for the projects that used it), each with a labelled daily trend. Export daily totals, projects, projects by model or models by project to CSV. Git worktrees are merged into their main repository. This replaces the separate History and Usage by Project windows.
- **Far fewer requests to Anthropic's usage API.** Anthropic limits how often usage can be requested, and the app used to hit that limit after waking from sleep. It now asks at most every 5 minutes while Claude is in use and every 15 minutes when idle, remembers the last answer across restarts and updates, waits calmly after wake, and backs off (honouring the server's retry hint) if it is rate limited.
- **Honest widgets.** If a refresh fails (for example a rate limit) the widgets show "Couldn't refresh · updated HH:mm", and old data is marked "Stale" by itself even if macOS never reloads the widget.
- Refresh interval in Settings is now 2 to 15 minutes.

Earlier versions: see the [release notes](https://github.com/israelio/claude-usage-widget/releases).

## Requirements

- macOS 14 or later
- Claude Code installed and signed in (the app reads its login from the Keychain and its logs from `~/.claude/projects`)
- To build: Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Install

### Homebrew

```sh
brew install --cask israelio/tap/claude-usage
```

The command is fully qualified, which is also how Homebrew's tap trust is granted for this one cask. The app updates itself, so `brew upgrade` leaves it alone unless you pass `--greedy`. To remove it and its data: `brew uninstall --zap --cask claude-usage`. The cask lives in [israelio/homebrew-tap](https://github.com/israelio/homebrew-tap).

### Download

1. Go to the **[latest release](https://github.com/israelio/claude-usage-widget/releases/latest)** and download `ClaudeUsage-<version>.dmg` (a `.sha256` checksum is next to it).
2. Open the DMG and drag **Claude Usage** onto **Applications**.
3. Launch it. Releases from 0.1.1 on are signed with a Developer ID and notarized by Apple, so it opens normally. (The older 0.1.0 was unsigned: right-click → **Open**.)
4. The app reads your Claude Code login from the Keychain through Apple's `security` tool, normally without a prompt. If macOS does ask, choose **Always Allow** ([details](#keychain-access)).
5. Look for the usage label in your menu bar. Click it to open the panel.
6. For the desktop widgets: right-click the desktop → **Edit Widgets** → search "Claude Usage".

## Updates

The app checks GitHub Releases every 6 hours. When a newer version exists it downloads the DMG, verifies the SHA-256 checksum and that the new app is notarized and signed by the same Developer ID team, then replaces itself and restarts. Turn this off under Settings > Updates ("Install updates automatically"); you will then get a notification instead. You can also use "Check for updates" in the About popover. Builds without a team ID (unsigned or development builds) only notify and link to the release page.

## Keychain access

Claude Code keeps your login (an OAuth token) in your macOS Keychain under the name "Claude Code-credentials". Your 5-hour and weekly limit percentages are only available from Anthropic's servers, and the app needs that same token to ask for them.

- **No password prompt in normal use.** The app reads the token through Apple's built-in `security` command-line tool, which that Keychain item already trusts (Claude Code writes the item with the same tool). It reads the token once per launch, keeps it in memory only, and re-reads only when the token is close to expiring or was rejected.
- **If macOS still asks** (for example on a Mac where the tool isn't trusted by the item), the dialog reads *"Claude Usage wants to access key 'Claude Code-credentials'"*. Enter your login password and choose **Always Allow**. Plain "Allow" is valid for one read only. Claude Code resets the item's trusted list whenever it refreshes its login, so that prompt can come back after a refresh.
- **What the app does with the token:** it uses it for calls to Anthropic's usage and account endpoints (`api.anthropic.com`) and nothing else. It never writes the token to disk, logs it, or changes anything in your Keychain.
- **If access is denied:** the app still works with token counts and cost from your local logs and an *estimated* usage percentage, but not the real limits.

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
- `App/` — SwiftUI menu bar app, popover, floating panel, settings, usage window
- `Widget/` — WidgetKit extension
- `project.yml` — XcodeGen project definition
- `scripts/make-dmg.sh` — builds a DMG

Run the tests:

```sh
swift test --package-path Packages/UsageCore
```

## Notes and limitations

- **Costs are API-equivalent estimates**, not what a subscription plan bills. Check the default prices in Settings; they may lag current Anthropic pricing.
- The usage endpoint is **undocumented** and may change. That is why the local fallback exists. It is also rate-limited; when the API answers HTTP 429 the app backs off automatically and keeps showing the last known values. Requests are kept to a minimum: at most every 5 minutes while Claude is in use, every 15 minutes when idle, and the last fetch is remembered across restarts.
- The login token is only read from the Keychain, kept in memory and sent to Anthropic's API; it is never logged or written to disk. See [Keychain access](#keychain-access).

## License

[MIT](LICENSE) © 2026 Ohad Israeli
