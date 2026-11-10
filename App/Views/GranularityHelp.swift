import SwiftUI

/// Explains Days vs Sessions in the Usage window (shown from the ⓘ button next to the Days | Sessions switch).
struct GranularityHelp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Days vs Sessions").font(.headline)
            block("Days", "One bar per calendar day, midnight to midnight in your local time. Best for daily spend and trends. Goes back 90 days.")
            block("Sessions", "One bar per Claude work session: a 5-hour window that starts at your first message, the same windows Claude's usage limit uses. Best for seeing what used up a limit window. Detail exists for roughly the last month (from your Claude Code logs) and then keeps growing.")
            Divider()
            Text("Same period, different cuts").font(.subheadline.bold())
            VStack(alignment: .leading, spacing: 4) {
                Text("\u{2022} \"7 days\" covers the last 7 days in both modes.")
                Text("\u{2022} Usage that crosses midnight is split between two days, but stays in one session.")
                Text("\u{2022} A session that began just before the period is counted whole, so Sessions totals can be slightly higher than Days totals.")
            }
            .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .padding(16).frame(width: 360)
    }

    private func block(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.bold())
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
