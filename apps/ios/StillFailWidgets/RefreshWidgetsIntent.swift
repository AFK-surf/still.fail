import AppIntents
import WidgetKit

/// This intent is declared only in the extension target. Refreshing a widget
/// never opens or relies on the main application, even after it was force quit.
struct RefreshWidgetsIntent: AppIntent {
    static var title: LocalizedStringResource = "刷新"
    static var openAppWhenRun: Bool = false
    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
