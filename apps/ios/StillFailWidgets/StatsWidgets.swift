import Charts
import SwiftUI
import WidgetKit

// MARK: Tasks per day

struct TaskStatsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "fail.still.stats", provider: SnapshotProvider()) { entry in
            TaskStatsView(entry: entry).widgetSurface()
        }
        .configurationDisplayName("任务统计")
        .description("每天的任务数量")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct TaskStatsView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry
    var body: some View {
        if let snapshot = entry.snapshot {
            Group {
                switch family {
                case .systemSmall: small(snapshot)
                case .systemLarge: large(snapshot)
                default: medium(snapshot)
                }
            }.widgetURL(WidgetLink.home)
        } else { WidgetUnsynced(symbol: "chart.bar") }
    }
    /// Small: today, and the week as bars.
    private func small(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            WidgetHeader(title: "任务统计", symbol: "chart.bar.fill")
            Spacer(minLength: 0)
            Text("今天").font(.caption2).foregroundStyle(.secondary)
            Text("\(snapshot.today)").font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(WidgetPalette.accent)
            DayBars(days: snapshot.lastDays(7), labels: .weekday).frame(height: 38)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
    /// Medium: today and the week in figures, two weeks as bars.
    private func medium(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(title: "任务统计", symbol: "chart.bar.fill", trailing: snapshot.workspace.isEmpty ? nil : snapshot.workspace)
            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    StatFigure(label: "今天", value: snapshot.today, emphasized: true)
                    StatFigure(label: "近 7 天", value: snapshot.total(days: 7))
                }.frame(width: 72, alignment: .leading)
                DayBars(days: snapshot.lastDays(14), labels: .weekday)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    /// Large: four figures, and a month of bars with its average.
    private func large(_ snapshot: WidgetSnapshot) -> some View {
        let month = snapshot.lastDays(30)
        let average = Double(snapshot.total(days: 30)) / Double(max(1, month.count))
        let peak = month.max { $0.count < $1.count }
        return VStack(alignment: .leading, spacing: 12) {
            WidgetHeader(title: "任务统计", symbol: "chart.bar.fill", trailing: snapshot.workspace.isEmpty ? nil : snapshot.workspace)
            HStack(spacing: 0) {
                StatFigure(label: "今天", value: snapshot.today, emphasized: true).frame(maxWidth: .infinity, alignment: .leading)
                StatFigure(label: "近 7 天", value: snapshot.total(days: 7)).frame(maxWidth: .infinity, alignment: .leading)
                StatFigure(label: "近 30 天", value: snapshot.total(days: 30)).frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text("日均").font(.caption2).foregroundStyle(.secondary)
                    Text(average.formatted(.number.precision(.fractionLength(0...1)))).font(.title3.weight(.semibold).monospacedDigit())
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            DayBars(days: month, labels: .date, average: average)
            if let peak, peak.count > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill").foregroundStyle(WidgetPalette.accent)
                    Text("峰值").foregroundStyle(.secondary)
                    Text(peak.date.formatted(.dateTime.month(.abbreviated).day()))
                    Text("·").foregroundStyle(.tertiary)
                    Text("\(peak.count) 项").monospacedDigit()
                }.font(.caption)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct StatFigure: View {
    let label: LocalizedStringKey
    let value: Int
    var emphasized = false
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            Text("\(value)").font(emphasized ? .title2.weight(.bold) : .title3.weight(.semibold)).monospacedDigit()
                .foregroundStyle(emphasized ? WidgetPalette.accent : .primary)
        }
    }
}

/// A bar per day, today in the accent; an optional average rule.
private struct DayBars: View {
    enum Labels { case weekday, date }
    let days: [WidgetSnapshot.Day]
    let labels: Labels
    var average: Double? = nil
    var body: some View {
        let today = days.last?.date
        Chart {
            ForEach(days, id: \.date) { day in
                BarMark(x: .value("Day", day.date, unit: .day), y: .value("Tasks", day.count), width: .ratio(0.62))
                    .foregroundStyle(day.date == today ? WidgetPalette.accent : WidgetPalette.accent.opacity(0.38))
                    .clipShape(RoundedRectangle(cornerRadius: 2.5, style: .continuous))
            }
            if let average, average > 0 {
                RuleMark(y: .value("Average", average))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(Color.secondary.opacity(0.7))
            }
        }
        .chartYAxis(labels == .date ? .automatic : .hidden)
        .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in AxisGridLine().foregroundStyle(Color.primary.opacity(0.08)); AxisValueLabel().font(.caption2) } }
        .chartXAxis {
            switch labels {
            case .weekday:
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel { if let date = value.as(Date.self) { Text(date.formatted(.dateTime.weekday(.narrow))).font(.system(size: 9)) } }
                }
            case .date:
                // A date every week, kept off both ends so none is cut at the edge.
                AxisMarks(values: days.indices.filter { (days.count - 1 - $0) % 7 == 3 }.map { days[$0].date }) { _ in
                    AxisValueLabel(format: .dateTime.month(.defaultDigits).day(), centered: true).font(.caption2)
                }
            }
        }
    }
}

// MARK: Weekly heat (orange)

struct TaskHeatmapWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "fail.still.heatmap", provider: SnapshotProvider()) { entry in
            TaskHeatmapView(entry: entry).widgetSurface()
        }
        .configurationDisplayName("活跃热力")
        .description("按周排开的每日任务数量")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct TaskHeatmapView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry
    var body: some View {
        if let snapshot = entry.snapshot {
            Group {
                switch family {
                case .systemSmall: small(snapshot)
                case .systemLarge: large(snapshot)
                default: medium(snapshot)
                }
            }.widgetURL(WidgetLink.home)
        } else { WidgetUnsynced(symbol: "square.grid.3x3.fill") }
    }
    private func small(_ snapshot: WidgetSnapshot) -> some View {
        let weeks = snapshot.weeks(7)
        return VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(title: "活跃热力", symbol: "flame.fill", trailing: "\(weekTotal(weeks.last))")
            HeatGrid(weeks: weeks, scale: scale(weeks), spacing: 3)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private func medium(_ snapshot: WidgetSnapshot) -> some View {
        let weeks = snapshot.weeks(17)
        return VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(title: "活跃热力", symbol: "flame.fill", trailing: "\(weeks.joined().compactMap { $0?.count }.reduce(0, +))")
            HeatGrid(weeks: weeks, scale: scale(weeks), spacing: 3, weekdays: true)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private func large(_ snapshot: WidgetSnapshot) -> some View {
        let weeks = snapshot.weeks(17)
        let days = weeks.joined().compactMap { $0 }
        let active = days.filter { $0.count > 0 }.count
        return VStack(alignment: .leading, spacing: 12) {
            WidgetHeader(title: "活跃热力", symbol: "flame.fill", trailing: snapshot.workspace.isEmpty ? nil : snapshot.workspace)
            HStack(spacing: 0) {
                figure("本周", weekTotal(weeks.last))
                figure("近 30 天", snapshot.total(days: 30))
                figure("活跃天数", active)
                figure("连续", streak(days))
            }
            HeatGrid(weeks: weeks, scale: scale(weeks), spacing: 4, weekdays: true, months: true, totals: true)
            HStack(spacing: 4) {
                if let peak = days.max(by: { $0.count < $1.count }), peak.count > 0 {
                    Image(systemName: "flame.fill").foregroundStyle(WidgetPalette.accent)
                    Text("峰值").foregroundStyle(.secondary)
                    Text(peak.date.formatted(.dateTime.month(.abbreviated).day()))
                    Text("·").foregroundStyle(.tertiary)
                    Text("\(peak.count) 项").monospacedDigit()
                }
                Spacer()
                Text("少").font(.caption2).foregroundStyle(.secondary)
                ForEach(0..<5) { RoundedRectangle(cornerRadius: 2.5, style: .continuous).fill(WidgetPalette.heat($0)).frame(width: 10, height: 10) }
                Text("多").font(.caption2).foregroundStyle(.secondary)
            }.font(.caption)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private func figure(_ label: LocalizedStringKey, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            Text("\(value)").font(.title3.weight(.semibold)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func weekTotal(_ week: [WidgetSnapshot.Day?]?) -> Int { (week ?? []).compactMap { $0?.count }.reduce(0, +) }
    private func scale(_ weeks: [[WidgetSnapshot.Day?]]) -> Int { max(1, weeks.joined().compactMap { $0?.count }.max() ?? 1) }
    /// Days in a row with tasks, up to today (today itself may still be empty).
    private func streak(_ days: [WidgetSnapshot.Day]) -> Int {
        var run = 0
        for (index, day) in days.reversed().enumerated() {
            if day.count > 0 { run += 1 } else if index > 0 { break }
        }
        return run
    }
}

/// Weeks as columns, the first weekday on top; square cells sized to the room there
/// is, with every other weekday named down the left and months over their first week.
private struct HeatGrid: View {
    let weeks: [[WidgetSnapshot.Day?]]
    let scale: Int
    let spacing: CGFloat
    var weekdays = false
    var months = false
    /// Each week's total as a bar under its column.
    var totals = false
    var body: some View {
        GeometryReader { proxy in
            let labelWidth: CGFloat = weekdays ? 16 : 0, monthHeight: CGFloat = months ? 14 : 0
            let columns = CGFloat(max(1, weeks.count))
            let side = max(4, min((proxy.size.width - labelWidth - spacing * (columns - 1)) / columns,
                                  (proxy.size.height - monthHeight - (totals ? 36 : 0) - spacing * 6) / 7))
            let barRoom = max(12, proxy.size.height - monthHeight - side * 7 - spacing * 6 - 10)
            let gridWidth = side * columns + spacing * (columns - 1)
            VStack(alignment: .leading, spacing: 0) {
                if months { MonthLabels(weeks: weeks, column: side + spacing).frame(width: gridWidth, height: monthHeight, alignment: .topLeading).padding(.leading, labelWidth) }
                HStack(alignment: .top, spacing: 0) {
                    if weekdays { WeekdayLabels(side: side, spacing: spacing).frame(width: labelWidth, alignment: .leading) }
                    HStack(alignment: .top, spacing: spacing) {
                        ForEach(weeks.indices, id: \.self) { column in
                            VStack(spacing: spacing) {
                                ForEach(0..<7, id: \.self) { row in
                                    let day = row < weeks[column].count ? weeks[column][row] : nil
                                    RoundedRectangle(cornerRadius: side * 0.24, style: .continuous)
                                        .fill(day.map { WidgetPalette.heat(level($0.count)) } ?? .clear)
                                        .frame(width: side, height: side)
                                }
                            }
                        }
                    }
                }
                if totals {
                    let sums = weeks.map { $0.compactMap { $0?.count }.reduce(0, +) }, most = max(1, sums.max() ?? 1)
                    HStack(alignment: .bottom, spacing: spacing) {
                        ForEach(sums.indices, id: \.self) { column in
                            RoundedRectangle(cornerRadius: min(3, side * 0.2), style: .continuous)
                                .fill(column == sums.count - 1 ? WidgetPalette.heat(4) : WidgetPalette.heat(2))
                                .frame(width: side, height: max(2, barRoom * CGFloat(sums[column]) / CGFloat(most)))
                        }
                    }
                    .frame(height: barRoom, alignment: .bottom)
                    .padding(.top, 10).padding(.leading, labelWidth)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
    }
    private func level(_ count: Int) -> Int { count == 0 ? 0 : min(4, Int(ceil(Double(count) / Double(scale) * 4))) }
}

private struct WeekdayLabels: View {
    let side: CGFloat
    let spacing: CGFloat
    var body: some View {
        let calendar = Calendar.current
        let symbols = calendar.veryShortWeekdaySymbols
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(0..<7, id: \.self) { row in
                // Every other day named, as calendars do, so the column stays light.
                Text(row % 2 == 1 ? symbols[(row + calendar.firstWeekday - 1) % 7] : "")
                    .font(.system(size: min(9, side * 0.7), weight: .medium)).foregroundStyle(.secondary)
                    .frame(height: side)
            }
        }
    }
}

/// A month's short name over the week it begins in.
private struct MonthLabels: View {
    let weeks: [[WidgetSnapshot.Day?]]
    /// One week's width, a cell and its gap.
    let column: CGFloat
    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(starts, id: \.0) { index, date in
                Text(date.formatted(.dateTime.month(.abbreviated))).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                    .fixedSize().offset(x: CGFloat(index) * column)
            }
        }
    }
    private var starts: [(Int, Date)] {
        let calendar = Calendar.current
        var result: [(Int, Date)] = []
        var previous: Int?
        for (column, week) in weeks.enumerated() {
            guard let first = week.compactMap({ $0 }).first else { continue }
            let month = calendar.component(.month, from: first.date)
            if previous != nil && month != previous && column < weeks.count - 1 { result.append((column, first.date)) }
            previous = month
        }
        return result
    }
}
