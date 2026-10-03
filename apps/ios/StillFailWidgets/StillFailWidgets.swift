import SwiftUI
import WidgetKit

@main
struct StillFailWidgets: WidgetBundle {
    var body: some Widget {
        DecisionsWidget()
        RecentTasksWidget()
        TaskStatsWidget()
        TaskHeatmapWidget()
    }
}
