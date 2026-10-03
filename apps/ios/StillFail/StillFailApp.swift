import SwiftUI

@main
struct StillFailApp: App {
    @State private var store = AppStore()
    @State private var widgetFeed = WidgetFeed()
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage(L10n.preferenceKey) private var appLanguage = "system"
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(store)
                .environment(\.locale, L10n.locale(for: appLanguage))
                .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
                .tint(Color("AccentColor"))
                .task { store.resume() }
                // Each scope (account, workspace, core restart) gets its own widget feed subscriptions.
                .task(id: store.scopeEpoch) { widgetFeed.restart(store: store) }
                .onOpenURL { url in store.open(url) }
                .onChange(of: appLanguage) { _, _ in L10n.notifyLanguageChanged() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { store.resume(); widgetFeed.resume() }
                    else { store.pause() }
                }
        }
    }
}

struct AppRootView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        Group {
            if let fatal = store.fatalMessage {
                VStack(spacing: 20) {
                    Label("暂时无法启动", systemImage: "exclamationmark.triangle").font(.title2).accessibilityIdentifier("startup.error.title")
                    Text(fatal).foregroundStyle(.secondary).accessibilityIdentifier("startup.error.message")
                    Button("重试") { store.resume() }.accessibilityIdentifier("startup.retry")
                }.padding()
            } else if !store.isReady {
                ProgressView("正在连接…").accessibilityIdentifier("startup.loading")
            } else {
                Group {
                    if store.accounts.isEmpty { NavigationStack { LoginView() } }
                    else if let workspace = store.selectedWorkspaceID { ConversationsView(workspace: workspace) }
                    else { NavigationStack { WorkspaceChooserView() } }
                }.id(store.scopeEpoch)
            }
        }
    }
}
