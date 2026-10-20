import SwiftUI
import WidgetKit

// MARK: Decision needed

struct DecisionsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "fail.still.decisions", provider: SnapshotProvider()) { entry in
            DecisionsView(entry: entry).widgetSurface()
        }
        .configurationDisplayName("需要决定")
        .description("等你决定的任务")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct DecisionsView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry
    var body: some View {
        if let snapshot = entry.snapshot {
            switch family {
            case .systemSmall: small(snapshot)
            case .systemLarge: large(snapshot)
            default: list(snapshot, count: 3, summaryLines: 0)
            }
        } else { WidgetUnsynced(symbol: "exclamationmark.bubble") }
    }
    /// Small: how many wait on you, and the latest one.
    private func small(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetHeader(title: "需要决定", symbol: "exclamationmark.bubble.fill")
            Spacer(minLength: 0)
            if let first = snapshot.decisions.first {
                Text("\(snapshot.decisionCount)").font(.system(size: 38, weight: .bold, design: .rounded)).foregroundStyle(WidgetPalette.accent)
                    .contentTransition(.numericText())
                Text(first.title).font(.footnote.weight(.semibold)).lineLimit(2)
                if !first.summary.isEmpty { Text(first.summary).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
            } else {
                Image(systemName: "checkmark.circle.fill").font(.title).foregroundStyle(.green)
                Text("暂无需要决定的任务").font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(snapshot.decisions.first?.link ?? WidgetLink.home)
    }
    /// Large: how many wait on you, then the four latest with what each asks.
    private func large(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeader(title: "需要决定", symbol: "exclamationmark.bubble.fill", trailing: snapshot.workspace.isEmpty ? nil : snapshot.workspace)
            if snapshot.decisions.isEmpty {
                WidgetEmpty(text: "暂无需要决定的任务", symbol: "checkmark.circle")
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(snapshot.decisionCount)").font(.system(size: 40, weight: .bold, design: .rounded)).foregroundStyle(WidgetPalette.accent)
                    Text("等你决定的任务").font(.subheadline).foregroundStyle(.secondary)
                }
                Divider()
                ForEach(snapshot.decisions.prefix(4)) { WidgetTaskRow(task: $0, summaryLines: 2) }
                Spacer(minLength: 0)
                if snapshot.decisionCount > 4 {
                    Text("还有 \(snapshot.decisionCount - 4) 项").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(WidgetLink.home)
    }
    /// Medium: the three latest, each with a line of what it asks.
    private func list(_ snapshot: WidgetSnapshot, count: Int, summaryLines: Int) -> some View {
        VStack(alignment: .leading, spacing: summaryLines > 0 ? 10 : 7) {
            WidgetHeader(title: "需要决定", symbol: "exclamationmark.bubble.fill", trailing: snapshot.decisionCount > 0 ? "\(snapshot.decisionCount)" : nil)
            if snapshot.decisions.isEmpty {
                WidgetEmpty(text: "暂无需要决定的任务", symbol: "checkmark.circle")
            } else {
                ForEach(snapshot.decisions.prefix(count)) { WidgetTaskRow(task: $0, summaryLines: summaryLines > 0 ? summaryLines : 1) }
                Spacer(minLength: 0)
                if snapshot.decisionCount > count {
                    Text("还有 \(snapshot.decisionCount - count) 项").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(WidgetLink.home)
    }
}

// MARK: Recent tasks

struct RecentTasksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "fail.still.recent", provider: SnapshotProvider()) { entry in
            RecentTasksView(entry: entry).widgetSurface()
        }
        .configurationDisplayName("最近的任务")
        .description("最近有进展的任务")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct RecentTasksView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry
    var body: some View {
        if let snapshot = entry.snapshot {
            switch family {
            case .systemSmall: small(snapshot)
            case .systemLarge: list(snapshot, count: 7, summaryLines: 1, spacing: 8)
            default: list(snapshot, count: 3, summaryLines: 0, spacing: 7)
            }
        } else { WidgetUnsynced(symbol: "clock.arrow.circlepath") }
    }
    /// Small: the one that moved last, with its line.
    private func small(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            WidgetHeader(title: "最近的任务", symbol: "clock.fill")
            Spacer(minLength: 0)
            if let task = snapshot.recent.first {
                HStack(spacing: 5) {
                    Circle().fill(WidgetPalette.tone(task.tone)).frame(width: 7, height: 7)
                    if let at = task.at { Text(at.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))).font(.caption2).foregroundStyle(.secondary) }
                }
                Text(task.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                if !task.summary.isEmpty { Text(task.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            } else {
                WidgetEmpty(text: "暂无任务", symbol: "tray")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(snapshot.recent.first?.link ?? WidgetLink.home)
    }
    private func list(_ snapshot: WidgetSnapshot, count: Int, summaryLines: Int, spacing: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            WidgetHeader(title: "最近的任务", symbol: "clock.fill", trailing: snapshot.workspace.isEmpty ? nil : snapshot.workspace)
            if snapshot.recent.isEmpty { WidgetEmpty(text: "暂无任务", symbol: "tray") }
            else {
                ForEach(snapshot.recent.prefix(count)) { WidgetTaskRow(task: $0, summaryLines: summaryLines) }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(WidgetLink.home)
    }
}
