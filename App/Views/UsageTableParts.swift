import SwiftUI
import UsageCore

/// Column widths shared by every table in the Usage window, so nested tables line up with the main one.
enum UsageColumns {
    static let cost: CGFloat = 80
    static let tokens: CGFloat = 70
    static let share: CGFloat = 170
}

/// Developer/screenshot aid: `CLAUDEUSAGE_ANONYMIZE_PROJECTS=1` shows generic project names (for README images).
enum UsageAnonymizer {
    static let enabled = ProcessInfo.processInfo.environment["CLAUDEUSAGE_ANONYMIZE_PROJECTS"] != nil
    private static let demoNames = ["web-app", "api-service", "mobile-client", "docs-site", "data-pipeline", "infra-tools", "design-system", "cli-tool"]

    /// The placeholder for the project ranked `index` (0-based, by cost).
    static func name(rank index: Int) -> String { index < demoNames.count ? demoNames[index] : "project-\(index - demoNames.count + 1)" }
}

/// Column titles; the active metric's column is bold.
struct UsageColumnHeader: View {
    let title: String
    let showCost: Bool
    var inset: CGFloat = 0

    var body: some View {
        HStack(spacing: 12) {
            Text(title).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, inset)
            Text("Cost").frame(width: UsageColumns.cost, alignment: .trailing).fontWeight(showCost ? .bold : .regular)
            Text("Tokens").frame(width: UsageColumns.tokens, alignment: .trailing).fontWeight(showCost ? .regular : .bold)
            Text("Share").frame(width: UsageColumns.share, alignment: .leading)
        }
    }
}

/// The Cost, Tokens and Share cells of a table row.
struct UsageValueCells: View {
    let cost: Double
    let tokens: Int
    let share: Double
    let showCost: Bool
    var dimmed = false

    var body: some View {
        Text(Format.cost(cost)).monospacedDigit().frame(width: UsageColumns.cost, alignment: .trailing)
            .fontWeight(showCost ? .semibold : .regular)
        Text(Format.tokens(tokens)).monospacedDigit().frame(width: UsageColumns.tokens, alignment: .trailing)
            .fontWeight(showCost ? .regular : .semibold)
        ShareBar(fraction: share, dimmed: dimmed).frame(width: UsageColumns.share)
    }
}

struct ShareBar: View {
    let fraction: Double
    var dimmed = false

    var body: some View {
        HStack(spacing: 8) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.10))
                    Capsule().fill(LinearGradient(colors: [.orange, .green], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(fraction > 0 ? 3 : 0, g.size.width * min(1, fraction)))
                        .opacity(dimmed ? 0.45 : 1)
                }
            }.frame(height: 8)
            Text("\(Int((fraction * 100).rounded()))%").font(.system(size: 11)).monospacedDigit()
                .foregroundStyle(.secondary).frame(width: 34, alignment: .trailing)
        }
    }
}

/// The disclosure triangle plus the row title.
struct UsageRowTitle: View {
    let title: String
    let open: Bool
    var dimmed = false
    var indent: CGFloat = 0

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary).frame(width: 10)
            Text(title).lineLimit(1).truncationMode(.middle).foregroundStyle(dimmed ? .secondary : .primary)
        }
        .padding(.leading, indent)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The bottom "Total" row.
struct UsageTotalRow: View {
    let total: Totals

    var body: some View {
        HStack(spacing: 12) {
            Text("Total").frame(maxWidth: .infinity, alignment: .leading)
            Text(Format.cost(total.cost)).monospacedDigit().frame(width: UsageColumns.cost, alignment: .trailing)
            Text(Format.tokens(total.tokens.total)).monospacedDigit().frame(width: UsageColumns.tokens, alignment: .trailing)
            Spacer().frame(width: UsageColumns.share)
        }
        .font(.system(size: 12, weight: .semibold)).padding(.horizontal, 8)
    }
}

/// Share of `total` in the selected metric, for a row whose cost-based share is `costShare`.
func usageShare(costShare: Double, tokens: Int, totalTokens: Int, showCost: Bool) -> Double {
    if showCost { return costShare }
    return totalTokens > 0 ? Double(tokens) / Double(totalTokens) : 0
}
