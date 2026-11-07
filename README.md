# Claude Usage Widget

macOS menu bar app and WidgetKit widgets showing Claude Code usage: 5-hour and weekly limits with pace, daily/90-day token cost history, and smart alerts.

## Build

1. Install XcodeGen: `brew install xcodegen`
2. Create `Local.xcconfig` from `Local.xcconfig.example` and set your Apple `DEVELOPMENT_TEAM` and `APP_GROUP_ID`. A Team ID is required for the widgets and the shared App Group to work. It is gitignored.
3. `xcodegen generate`
4. Open `ClaudeUsageWidget.xcodeproj` in Xcode and run, or build from the command line:
   `xcodebuild -project ClaudeUsageWidget.xcodeproj -scheme ClaudeUsageWidget -configuration Debug -destination 'platform=macOS' -allowProvisioningUpdates build`

Unsigned builds (add `CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=""`) run the menu bar app, which falls back to `~/Library/Application Support/ClaudeUsageWidget/`, but widgets cannot read the data without the App Group.

Core logic lives in `Packages/UsageCore`; run its tests with `cd Packages/UsageCore && swift test`.

## Notes

- Costs are API-equivalent estimates computed from local logs in `~/.claude/projects` and the editable price table. They are not what a subscription plan bills.
- Live limits come from an undocumented Claude usage endpoint, using the Claude Code OAuth token from the Keychain (macOS asks for access on first launch). The endpoint may change or break. When it is unavailable, the app falls back to a local estimate based on configurable token budgets and marks it as estimated.
