import SwiftUI
import UsageCore

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var thresholdText = ""
    @FocusState private var thresholdFocused: Bool

    var body: some View {
        Form {
            Section("Display") {
                Picker("Menu bar", selection: $settings.prefs.menuBarMode) {
                    ForEach(MenuBarMode.allCases) { Text($0.rawValue).tag($0) }
                }
                Toggle("Floating always-on-top panel", isOn: $settings.prefs.floatingPanel)
                Stepper("Refresh every \(settings.prefs.pollSeconds)s", value: $settings.prefs.pollSeconds, in: 30...600, step: 30)
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
        .formStyle(.grouped).frame(width: 560, height: 620)
        .onAppear { thresholdText = Self.format(settings.prefs.alerts.thresholds) }
        .onDisappear(perform: commitThresholds)
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
