import SwiftUI
import Charts
import AppKit
import UsageCore

struct HistoryView: View {
    @ObservedObject var service: UsageService
    @State private var showCost = true

    var body: some View {
        let data = service.daily(days: 90)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Last 90 days").font(.title2.bold())
                Spacer()
                Picker("", selection: $showCost) { Text("Cost").tag(true); Text("Tokens").tag(false) }
                    .pickerStyle(.segmented).frame(width: 160)
                Button("Export CSV") { export(data) }
            }
            Chart(data) { p in
                BarMark(x: .value("Day", p.day, unit: .day),
                        y: .value("v", showCost ? p.cost : Double(p.tokens.total)))
                    .foregroundStyle(.orange.gradient)
            }.frame(height: 220)
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading) {
                    Text("Last 30 days by model").font(.headline)
                    ForEach(service.summary.modelShare, id: \.model) { m in
                        HStack { Text(PriceTable.displayName(m.model)); Spacer(); Text("\(Int((m.fraction * 100).rounded()))%") }
                    }
                }
                VStack(alignment: .leading) {
                    Text("Totals (90d)").font(.headline)
                    let t = data.reduce(into: Totals.zero) { $0.tokens += $1.tokens; $0.cost += $1.cost }
                    Text("Tokens: \(Format.tokens(t.tokens.total))")
                    Text("Cost: \(Format.cost(t.cost)) (API-equivalent)")
                }
            }
            Spacer()
        }
        .padding(20).frame(minWidth: 640, minHeight: 460)
    }

    private func export(_ data: [DailyPoint]) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "claude-usage-90d.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var csv = "date,input,output,cache_write,cache_read,cost_usd\n"
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        for p in data {
            csv += "\(f.string(from: p.day)),\(p.tokens.input),\(p.tokens.output),\(p.tokens.cacheWrite),\(p.tokens.cacheRead),\(String(format: "%.4f", p.cost))\n"
        }
        try? csv.write(to: url, atomically: true, encoding: .utf8)
    }
}
