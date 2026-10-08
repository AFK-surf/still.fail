import SwiftUI
import UIKit

extension JSONValue {
    func text(_ key: String, fallback: String = "") -> String { self[key].stringValue ?? fallback }
    func flag(_ key: String) -> Bool { self[key].boolValue == true }
}

struct ViewRecord: Identifiable {
    let id: String
    let value: JSONValue
    static func decode(_ values: [JSONValue], key: String = "id", prefix: String = "") -> [Self] {
        values.enumerated().map { index, value in
            Self(id: prefix + (value[key].stringValue ?? value[key].intValue.map(String.init) ?? String(index)), value: value)
        }
    }
}

struct WorkspaceChoice: Identifiable {
    var id: String { accountID + ":" + workspaceID }
    let accountID: String
    let accountEmail: String
    let workspaceID: String
    let name: String
    let role: String
    let value: JSONValue
    static func decode(_ groups: [JSONValue]) -> [Self] {
        groups.flatMap { group in
            guard let account = group["account"]["sub"].stringValue else { return [Self]() }
            return group["workspaces"].arrayValue.compactMap { workspace in
                guard let id = workspace["id"].stringValue else { return nil }
                return Self(accountID: account, accountEmail: group["account"].text("email"), workspaceID: id,
                            name: workspace.text("name"), role: workspace.text("role"), value: workspace)
            }
        }
    }
}

/// One subscription per view identity, cancelled when that identity is destroyed.
/// Navigation transitions can deliver a late onDisappear after the next onAppear
/// (a cancelled back swipe), so appearance never cancels or replaces the topic.
@MainActor final class TopicLease {
    private var topics: [String: CoreTopic] = [:]
    var topic: CoreTopic? { topics[""] }
    func replace(_ next: CoreTopic, key: String = "") { topics[key]?.cancel(); topics[key] = next }
    func drop(key: String) { topics.removeValue(forKey: key)?.cancel() }
    func cancelAll() { topics.values.forEach { $0.cancel() }; topics.removeAll() }
    deinit {
        let topics = Array(topics.values)
        if Thread.isMainThread { MainActor.assumeIsolated { topics.forEach { $0.cancel() } } }
        else { Task { @MainActor in topics.forEach { $0.cancel() } } }
    }
}

/// Owns exactly one core subscription for this view identity. A scope change destroys its parent.
struct TopicContent<Content: View>: View {
    @Environment(AppStore.self) private var store
    let name: String
    var params: [String: JSONValue] = [:]
    @ViewBuilder let content: (JSONValue) -> Content
    @State private var lease = TopicLease()
    @State private var topic: CoreTopic?

    var body: some View {
        Group {
            if let value = topic?.value {
                VStack(spacing: 0) {
                    if let error = topic?.error {
                        FailureNotice(message: error.message, retained: true, retry: restart)
                    }
                    content(value)
                }
            } else if let error = topic?.error {
                VStack(spacing: 16) {
                    Label("暂时无法读取", systemImage: "exclamationmark.triangle")
                        .font(.headline).accessibilityIdentifier("topic.error.title")
                    Text(LocalizedStringKey(error.message)).foregroundStyle(.secondary).accessibilityIdentifier("topic.error.message")
                    Button("重试", action: restart).accessibilityIdentifier("topic.retry")
                }.padding()
            } else {
                ProgressView("正在读取…").accessibilityIdentifier("topic.loading")
            }
        }
        // Overlays on this content (the floating new-chat button) align to the
        // full page, never to a centred loading indicator.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // A reappearing view keeps its live subscription; only a retry replaces it.
        .task { if topic == nil { subscribe() } }
    }
    private func subscribe() {
        let next = store.subscribe(name, params: params)
        lease.replace(next); topic = next
    }
    private func restart() { subscribe() }
}

struct FailureNotice: View {
    let message: String
    var retained = false
    var retry: (() -> Void)?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey(message)).accessibilityIdentifier("operation.error.message")
            if retained { Text("正在显示上次读取的数据，尚未确认最新状态。").font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("topic.retained") }
            if let retry { Button("重试", action: retry).accessibilityIdentifier("operation.retry") }
        }.font(.subheadline).padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground))
            .accessibilityElement(children: .contain)
    }
}

@MainActor @Observable final class ViewOperation {
    var busy = false
    var error: String?
    var code: String?
    func run(_ operation: () async throws -> Void) async {
        guard !busy else { return }
        busy = true; error = nil; code = nil
        defer { busy = false }
        do { try await operation() }
        catch let failure as CoreFailure { error = failure.message; code = failure.code }
        catch { self.error = "操作暂时未能完成，请检查连接后重试。" }
    }
}

struct OperationSection: View {
    let operation: ViewOperation
    var body: some View {
        if operation.busy { ProgressView("正在处理…").accessibilityIdentifier("operation.loading") }
        if let error = operation.error { FailureNotice(message: error) }
    }
}

struct RenameSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let initial: String
    let save: (String) async throws -> Void
    @State private var name = ""
    @State private var operation = ViewOperation()
    var body: some View {
        NavigationStack {
            Form {
                TextField("名字", text: $name).accessibilityIdentifier("rename.name")
                OperationSection(operation: operation)
            }.navigationTitle(LocalizedStringKey(title)).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.accessibilityIdentifier("rename.cancel") }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") { Task { await operation.run { try await save(name.trimmingCharacters(in: .whitespacesAndNewlines)); dismiss() } } }
                            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || operation.busy).accessibilityIdentifier("rename.save")
                    }
                }
        }.onAppear { name = initial }.interactiveDismissDisabled(operation.busy)
    }
}

struct MessageText: View {
    let text: String
    var body: some View {
        MarkdownMessage(text: text).frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("message.body")
    }
}

/// One lookup for every model mark. Anthropic's models are shown as Claude.
enum ModelLogo {
    static func image(maker: String, runtime: String = "") -> UIImage? {
        var id = maker.isEmpty ? (runtime == "claude" ? "anthropic" : runtime.isEmpty ? "" : "openai") : maker
        if id == "anthropic" || id == "claude" { id = "claude" }
        return id.isEmpty ? nil : UIImage(named: "Model-" + id)
    }
}
