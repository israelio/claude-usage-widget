import SwiftUI
import UsageCore
import WidgetKit

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var thresholdText = ""
    @FocusState private var thresholdFocused: Bool
    @StateObject private var widgetStatus = WidgetStatus()

    var body: some View {
        Form {
            Section("Display") {
                Picker("Menu bar", selection: $settings.prefs.menuBarMode) {
                    ForEach(MenuBarMode.allCases) { Text($0.label).tag($0) }
                }
                if settings.prefs.menuBarMode == .custom {
                    GroupBox("Show in menu bar") {
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle("Status dot", isOn: $settings.prefs.menuBarItems.statusDot)
                            Toggle("5-hour session %", isOn: $settings.prefs.menuBarItems.session)
                            Toggle("Pace vs even use", isOn: $settings.prefs.menuBarItems.pace)
                                .disabled(!settings.prefs.menuBarItems.session)
                            Toggle("Weekly limit %", isOn: $settings.prefs.menuBarItems.weekly)
                            Toggle("Per-model weekly (e.g. Fable)", isOn: $settings.prefs.menuBarItems.weeklyModel)
                            Toggle("Today's cost", isOn: $settings.prefs.menuBarItems.todayCost)
                            Toggle("Session reset countdown", isOn: $settings.prefs.menuBarItems.resetCountdown)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                    }
                }
                if settings.prefs.menuBarMode != .iconOnly {
                    LabeledContent("Preview") { Text(preview).font(.system(.body, design: .monospaced)) }
                }
                Picker("Show usage as", selection: $settings.prefs.showRemaining) {
                    Text("Used").tag(false)
                    Text("Left").tag(true)
                }
                Toggle("Floating always-on-top panel", isOn: $settings.prefs.floatingPanel)
                Stepper("Refresh at most every \(settings.prefs.pollSeconds / 60) min", value: $settings.prefs.pollSeconds, in: 120...900, step: 60)
                Text("Anthropic limits how often usage can be requested; shorter intervals may get blocked.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Notifications") {
                Toggle("Burn-rate warning", isOn: $settings.prefs.alerts.burnRate)
                Toggle("Reset notice", isOn: $settings.prefs.alerts.resetNotice)
                Toggle("Daily digest", isOn: $settings.prefs.alerts.dailyDigest)
                Toggle("Weekly digest (Mondays)", isOn: $settings.prefs.alerts.weeklyDigest)
                Stepper("Digest hour: \(settings.prefs.alerts.digestHour):00", value: $settings.prefs.alerts.digestHour, in: 0...23)
                Toggle("Quiet hours (22:00–08:00)", isOn: Binding(
                    get: { settings.prefs.alerts.quietStartHour != nil },
                    set: { settings.prefs.alerts.quietStartHour = $0 ? 22 : nil; settings.prefs.alerts.quietEndHour = $0 ? 8 : nil }))
                TextField("Thresholds %", text: $thresholdText)
                    .focused($thresholdFocused)
                    .onSubmit(commitThresholds)
                    .onChange(of: thresholdFocused) { _, f in if !f { commitThresholds() } }
            }
            Section("Desktop widgets") {
                LabeledContent("Status") {
                    switch widgetStatus.placedCount {
                    case .none: Text("Checking…").foregroundStyle(.secondary)
                    case .some(0): Text("None added yet").foregroundStyle(.secondary)
                    case .some(let n): Text("\(n) widget\(n == 1 ? "" : "s") on your desktop").foregroundStyle(.green)
                    }
                }
                HStack {
                    Button("How to add widgets…") { WidgetGuideWindowController.shared.show(firstRun: false) }
                    Button("Widget style (Full-color / Monochrome)…") { DesktopSettingsLink.open() }
                    Button("Refresh widgets") { WidgetCenter.shared.reloadAllTimelines() }
                }
                Text("macOS doesn't let apps place widgets for you; Edit Widgets on the desktop does.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Updates") {
                Toggle("Install updates automatically", isOn: $settings.prefs.autoUpdate)
                Text("Checks GitHub for new releases every 6 hours.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Fallback estimate (used only when the usage API is unavailable)") {
                Stepper("5h budget: \(Format.tokens(settings.prefs.planLimits.fiveHourTokens))",
                        value: $settings.prefs.planLimits.fiveHourTokens, in: 100_000...100_000_000, step: 500_000)
                Stepper("Weekly budget: \(Format.tokens(settings.prefs.planLimits.weeklyTokens))",
                        value: $settings.prefs.planLimits.weeklyTokens, in: 1_000_000...2_000_000_000, step: 5_000_000)
            }
            Section("Prices (USD per million tokens)") {
                ForEach(settings.prefs.prices.byFamily.keys.sorted(), id: \.self) { fam in
                    HStack {
                        Text(fam.capitalized).frame(width: 60, alignment: .leading)
                        priceField("in", fam, \.input); priceField("out", fam, \.output)
                        priceField("c-write", fam, \.cacheWrite); priceField("c-read", fam, \.cacheRead)
                    }
                }
                Button("Reset to defaults") { settings.prefs.prices = .defaults }
            }
        }
        .formStyle(.grouped).frame(width: 560, height: 700)
        .onAppear { thresholdText = Self.format(settings.prefs.alerts.thresholds); widgetStatus.start() }
        .onDisappear { commitThresholds(); widgetStatus.stop() }
    }

    /// Sample data so the effect of each toggle is visible without waiting for real numbers.
    private var preview: String {
        let now = Date()
        let l = LimitsSnapshot(fetchedAt: now,
                               fiveHour: LimitWindow(utilization: 42, resetsAt: now.addingTimeInterval(2 * 3600 + 14 * 60 + 30)),
                               sevenDay: LimitWindow(utilization: 71, resetsAt: nil),
                               extra: ["fable": LimitWindow(utilization: 78, resetsAt: nil)])
        let t = MenuBarText.make(limits: l, todayCost: 8.69, items: settings.prefs.effectiveMenuBarItems,
                                 showRemaining: settings.prefs.showRemaining, now: now)
        return t.isEmpty ? "(icon only)" : t
    }

    private static func format(_ t: [Int]) -> String { t.map(String.init).joined(separator: ", ") }

    private func commitThresholds() {
        let parsed = thresholdText.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .filter { (1...100).contains($0) }
        settings.prefs.alerts.thresholds = parsed
        thresholdText = Self.format(parsed)
    }

    private func priceField(_ label: String, _ fam: String, _ kp: WritableKeyPath<ModelPrice, Double>) -> some View {
        TextField(label, value: Binding(
            get: { settings.prefs.prices.byFamily[fam]?[keyPath: kp] ?? 0 },
            set: { settings.prefs.prices.byFamily[fam]?[keyPath: kp] = $0 }), format: .number)
            .textFieldStyle(.roundedBorder)
    }
}
