import SwiftUI
import WidgetKit

// MARK: Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    /// nil until the app has written one (never opened, or signed out).
    let snapshot: WidgetSnapshot?
}

/// Every widget reads the app's latest snapshot. The app reloads the timelines when it
/// writes; on its own, a widget re-reads at the next midnight (the day rolls over) or
/// in half an hour, whichever comes first.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: Date(), snapshot: .preview) }
    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let saved = WidgetSnapshot.load()?.aligned(to: Date())
        completion(SnapshotEntry(date: Date(), snapshot: saved ?? (context.isPreview ? .preview : nil)))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let now = Date(), calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(3600)
        let next = min(midnight, now.addingTimeInterval(30 * 60))
        completion(Timeline(entries: [SnapshotEntry(date: now, snapshot: WidgetSnapshot.load()?.aligned(to: now))], policy: .after(next)))
    }
}

extension WidgetSnapshot {
    /// A snapshot written yesterday still ends on today: the days since count zero.
    func aligned(to now: Date, calendar: Calendar = .current) -> WidgetSnapshot {
        guard let last = days.last?.date else { return self }
        let today = calendar.startOfDay(for: now)
        let missing = calendar.dateComponents([.day], from: last, to: today).day ?? 0
        guard missing > 0 else { return self }
        var copy = self
        let added = (1...min(missing, WidgetSnapshot.dayCount)).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: last).map { Day(date: $0, count: 0) }
        }
        copy.days = Array((days + added).suffix(WidgetSnapshot.dayCount))
        return copy
    }

    static var preview: WidgetSnapshot {
        let calendar = Calendar.current, today = calendar.startOfDay(for: Date())
        let pattern = [3, 5, 2, 0, 7, 4, 1, 6, 8, 2, 0, 3, 9, 5, 1, 0, 4]
        let days = (0..<dayCount).reversed().map { offset in
            Day(date: calendar.date(byAdding: .day, value: -offset, to: today)!, count: pattern[(offset * 7 + offset / 5) % pattern.count])
        }
        func task(_ id: String, _ title: String, _ summary: String, _ tone: String, _ minutes: Double) -> Task {
            Task(id: id, title: title, summary: summary, tone: tone, at: Date().addingTimeInterval(-minutes * 60), unread: tone == "alert", link: nil)
        }
        return WidgetSnapshot(updatedAt: Date(), workspace: "still.fail", decisions: [
            task("a", "Release checklist", "Ship 0.4 today, or hold for the fix?", "wait", 4),
            task("b", "Landing page copy", "Pick one of three headlines", "wait", 32),
            task("c", "Billing migration", "Approve the schema change", "wait", 95)], decisionCount: 3,
            recent: [
            task("d", "Fix flaky login test", "All green after the retry fix", "busy", 1),
            task("a", "Release checklist", "Ship 0.4 today, or hold for the fix?", "wait", 4),
            task("e", "Weekly metrics", "Report posted to #ops", "", 18),
            task("b", "Landing page copy", "Pick one of three headlines", "wait", 32),
            task("f", "Crash in share sheet", "Root cause found", "alert", 60),
            task("g", "Docs cleanup", "Done", "", 140),
            task("c", "Billing migration", "Approve the schema change", "wait", 195)], days: days)
    }
}

// MARK: Shared look

enum WidgetPalette {
    static let accent = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.965, green: 0.639, blue: 0.514, alpha: 1) : UIColor(red: 0.725, green: 0.278, blue: 0.122, alpha: 1) })
    /// The heat scale: an empty day, then four steps of orange.
    static func heat(_ level: Int) -> Color {
        let orange = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 1, green: 0.55, blue: 0.22, alpha: 1) : UIColor(red: 0.95, green: 0.45, blue: 0.1, alpha: 1) })
        switch level {
        case 0: return Color.primary.opacity(0.07)
        case 1: return orange.opacity(0.28)
        case 2: return orange.opacity(0.5)
        case 3: return orange.opacity(0.75)
        default: return orange
        }
    }
    static func tone(_ tone: String) -> Color {
        switch tone {
        case "alert": return .red
        case "wait": return .orange
        case "busy": return .green
        default: return .secondary.opacity(0.5)
        }
    }
}

struct WidgetHeader: View {
    let title: LocalizedStringKey
    let symbol: String
    var trailing: String? = nil
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.caption.weight(.semibold)).foregroundStyle(WidgetPalette.accent)
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 4)
            if let trailing { Text(trailing).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(.secondary) }
        }
    }
}

/// Shown until the app has written a snapshot.
struct WidgetUnsynced: View {
    let symbol: String
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.title2).foregroundStyle(WidgetPalette.accent)
            Text("打开 still.fail 同步").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WidgetEmpty: View {
    let text: LocalizedStringKey
    let symbol: String
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.tertiary)
            Text(text).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One task: its state dot, title, when it last moved, and (with room) its line.
struct WidgetTaskRow: View {
    let task: WidgetSnapshot.Task
    var summaryLines = 0
    var body: some View {
        let row = HStack(alignment: .firstTextBaseline, spacing: 7) {
            Circle().fill(WidgetPalette.tone(task.tone)).frame(width: 6, height: 6).alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline) {
                    Text(task.title).font(.subheadline.weight(task.unread ? .bold : .semibold)).lineLimit(1)
                    Spacer(minLength: 4)
                    if let at = task.at { Text(at.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))).font(.caption2.monospacedDigit()).foregroundStyle(.tertiary).lineLimit(1).frame(maxWidth: 64, alignment: .trailing) }
                }
                if summaryLines > 0 && !task.summary.isEmpty {
                    Text(task.summary).font(.caption).foregroundStyle(.secondary).lineLimit(summaryLines)
                }
            }
        }
        if let link = task.link { Link(destination: link) { row } } else { row }
    }
}

extension View {
    func widgetSurface() -> some View {
        containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
    }
}

#Preview("Decisions", as: .systemMedium) { DecisionsWidget() } timeline: { SnapshotEntry(date: .now, snapshot: .preview) }
#Preview("Recent", as: .systemLarge) { RecentTasksWidget() } timeline: { SnapshotEntry(date: .now, snapshot: .preview) }
#Preview("Stats", as: .systemSmall) { TaskStatsWidget() } timeline: { SnapshotEntry(date: .now, snapshot: .preview) }
#Preview("Heat", as: .systemLarge) { TaskHeatmapWidget() } timeline: { SnapshotEntry(date: .now, snapshot: .preview); SnapshotEntry(date: .now, snapshot: nil) }
