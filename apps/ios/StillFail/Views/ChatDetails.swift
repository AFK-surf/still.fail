import SwiftUI
import UIKit

struct ChatHistorySheet: View {
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    let station: String
    let agents: [JSONValue]
    @State private var selected = ""
    private var keys: [String] { agents.map { $0["session"].text("key", fallback: $0.text("key")) }.filter { !$0.isEmpty } }
    var body: some View {
        let _ = locale.identifier
        NavigationStack {
            VStack(spacing: 0) {
                if keys.count > 1 {
                    Picker(L10n.text("模型"), selection: $selected) {
                        ForEach(ViewRecord.decode(agents, key: "key")) { record in
                            let agent = record.value
                            let session = agent["session"]
                            Text(L10n.projected(session.text("agentText", fallback: L10n.text("模型")))).tag(session.text("key", fallback: agent.text("key")))
                        }
                    }.pickerStyle(.menu).padding(.horizontal)
                }
                if keys.isEmpty {
                    ContentUnavailableView(L10n.text("暂无执行历史"), systemImage: "clock.arrow.circlepath", description: Text(L10n.text("发送消息后，这里会显示 agent 的执行记录。")))
                } else {
                    ExecutionHistoryView(station: station, key: selected.isEmpty ? keys[0] : selected).id(selected.isEmpty ? keys[0] : selected)
                }
            }
            .navigationTitle(L10n.text("执行历史")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("完成")) { dismiss() } } }
        }.onChange(of: keys, initial: true) { _, values in
            if !values.contains(selected) { selected = values.first ?? "" }
        }
    }
}

struct ExecutionHistoryView: View {
    @Environment(\.locale) private var locale
    @Environment(AppStore.self) private var store
    let station: String
    let key: String
    @State private var operation = ViewOperation()
    var body: some View {
        let _ = locale.identifier
        TopicContent(name: "history", params: ["station": .string(station), "key": .string(key)]) { value in
            HistoryMessageList(value: value, busy: operation.busy) {
                Task { await operation.run { _ = try await store.call("history.older", params: ["station": .string(station), "key": .string(key)]) } }
            }
            .overlay(alignment: .bottom) {
                if let error = operation.error { Text(error).font(.footnote).foregroundStyle(.red).padding().background(.regularMaterial) }
            }
        }.navigationTitle(L10n.text("执行历史")).navigationBarTitleDisplayMode(.inline).accessibilityIdentifier("history.page")
    }
}

enum HistoryRendering {
    private final class Entry { let text: String; init(_ text: String) { self.text = text } }
    private static let cache: NSCache<NSString, Entry> = { let cache = NSCache<NSString, Entry>(); cache.countLimit = 128; cache.totalCostLimit = 8 * 1024 * 1024; return cache }()
    static func cachedTool(_ text: String, name: String) -> String? { cache.object(forKey: (name + "\u{001F}" + text) as NSString)?.text }
    static func tool(_ text: String, name: String) -> String {
        let key = name + "\u{001F}" + text
        if let cached = cache.object(forKey: key as NSString) { return cached.text }
        let rendered = renderTool(text, name: name)
        cache.setObject(Entry(rendered), forKey: key as NSString, cost: rendered.utf8.count)
        return rendered
    }
    private static func renderTool(_ text: String, name: String) -> String {
        if let data = text.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]), let json = String(data: pretty, encoding: .utf8) {
            return fence(json, language: "json")
        }
        let name = name.lowercased()
        if ["bash", "terminal", "exec", "command", "read", "edit"].contains(where: name.contains) { return fence(text, language: text.hasPrefix("diff ") ? "diff" : "text") }
        return text
    }
    static func fence(_ text: String, language: String) -> String {
        let longest = text.components(separatedBy: "\n").map { line in line.trimmingCharacters(in: .whitespaces).prefix(while: { $0 == "`" }).count }.max() ?? 0
        let delimiter = String(repeating: "`", count: max(3, longest + 1))
        return "\(delimiter)\(language)\n\(text)\n\(delimiter)"
    }
}

struct ChatInfoSheet: View {
    @Environment(\.locale) private var locale
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let route: ChatRoute
    let workspace: String
    let value: JSONValue
    let rename: () -> Void
    let archive: () -> Void
    let latest: () -> Void
    let checkSend: (() -> Void)?
    @State private var operation = ViewOperation()
    private var agents: [ViewRecord] { ViewRecord.decode(value["agents"].arrayValue, key: "key") }
    var body: some View {
        let _ = locale.identifier
        NavigationStack {
            TopicContent(name: "stations", params: ["scope": .string(workspace)]) { stations in
                List {
                    Section(L10n.text("模型与账号")) {
                        ForEach(agents) { agent in
                            let session = agent.value["session"], key = session.text("key", fallback: agent.value.text("key"))
                            let label = ChatTimeline.agentLabel(L10n.projected(session.text("agentText", fallback: session.text("model"))))
                            let account = agent.value["account"].text("name", fallback: agent.value["profile"].text("name"))
                            NavigationLink { SessionModelPicker(station: route.station, key: key) } label: {
                                HStack(spacing: 12) {
                                    ModelAvatar(maker: session["maker"].text("id"), runtime: session.text("runtime"))
                                        .frame(width: 22, height: 22).padding(9)
                                        .background(Color(uiColor: ChatPalette.tile), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text(label.model).font(.body.weight(.semibold)).lineLimit(1)
                                            if let effort = label.effort {
                                                Text(L10n.text(effort)).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                                                    .padding(.horizontal, 7).padding(.vertical, 2)
                                                    .background(Color(uiColor: ChatPalette.tile), in: Capsule())
                                            }
                                        }
                                        Text(L10n.text("切换模型与思考强度")).font(.caption).foregroundStyle(.secondary)
                                    }
                                }.padding(.vertical, 2)
                            }.disabled(value.flag("offline") || value.flag("archived"))
                            NavigationLink { SessionModelPicker(station: route.station, key: key, showAccounts: true) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "person.crop.circle").font(.system(size: 18)).foregroundStyle(.secondary)
                                        .frame(width: 40)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(account.isEmpty ? L10n.text("自动选择") : account).lineLimit(1)
                                        Text(L10n.text("切换账号")).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }.disabled(value.flag("offline") || value.flag("archived"))
                            if let quota = agent.value["account"]["quotaLine"]["text"].stringValue { Text(L10n.projected(quota)).font(.caption).foregroundStyle(.secondary) }
                        }
                        if agents.isEmpty { Text(L10n.text("对话创建后即可查看模型与账号。" )).foregroundStyle(.secondary) }
                    }
                    Section(L10n.text("基础信息")) {
                        LabeledContent(L10n.text("名称"), value: value.text("title"))
                        LabeledContent(L10n.text("来自"), value: value.text("place", fallback: "StillFail"))
                        LabeledContent(L10n.text("发起"), value: value["thread"]["creator"]["shown"].text("display", fallback: L10n.text("未记录")))
                        LabeledContent(L10n.text("参与"), value: L10n.format("%d 人", value["people"].arrayValue.count))
                        LabeledContent(L10n.text("创建"), value: ChatTimeline.timestamp(value["thread"], includeDate: true))
                        ForEach(agents) { agent in
                            let session = agent.value["session"]
                            LabeledContent(L10n.text("运行状态"), value: L10n.projected(session.text("processText", fallback: session.text("statusText"))))
                            if !session.text("workspace").isEmpty { LabeledContent(L10n.text("工作目录"), value: session.text("workspace")) }
                            if case .array(let turns) = agent.value["turns"] { LabeledContent(L10n.text("轮次"), value: String(turns.count)) }
                            if !session.text("runtimeSessionId").isEmpty { LabeledContent(L10n.text("运行会话"), value: session.text("runtimeSessionId")).font(.caption).textSelection(.enabled) }
                            AgentContextRows(station: route.station, key: session.text("key", fallback: agent.value.text("key")))
                        }
                    }
                    Section(L10n.text("节点健康")) {
                        if let node = stations.arrayValue.first(where: { $0.text("station") == route.station || $0.text("id") == route.station.split(separator: "/").last.map(String.init) }) {
                            NodeHealthRows(node: node)
                        } else { Text(L10n.text("正在读取节点状态…")).foregroundStyle(.secondary) }
                    }
                    Section {
                        Button(L10n.text("重命名会话"), systemImage: "pencil") { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { rename() } }.accessibilityIdentifier("chat.rename")
                        if value["pinned"].boolValue != nil {
                            Button(L10n.text(value.flag("pinned") ? "取消固定" : "固定到列表顶部"), systemImage: "pin") { pin() }
                                .disabled(operation.busy || value.flag("offline"))
                        }
                        Button(L10n.text(value.flag("archived") ? "恢复会话" : "归档会话"), systemImage: "archivebox") { archive(); dismiss() }.accessibilityIdentifier("chat.archive")
                        if value.flag("newer") { Button(L10n.text("查看最新消息"), action: latest) }
                        if let checkSend { Button(L10n.text("查看发送状态"), action: checkSend) }
                    }
                    OperationSection(operation: operation)
                }.listStyle(.insetGrouped)
            }
            .navigationTitle(L10n.text("对话信息")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("完成")) { dismiss() } } }
        }
    }
    private func pin() {
        Task { await operation.run {
            _ = try await store.call("chat.pin", params: ["station": .string(route.station), "session": .string(route.session), "pinned": .bool(!value.flag("pinned"))])
        } }
    }
}

private struct ModelAvatar: View {
    let maker: String
    var runtime = ""
    var body: some View {
        if let image = ModelLogo.image(maker: maker, runtime: runtime) { Image(uiImage: image).resizable().scaledToFit() }
        else { Image(systemName: "sparkles").resizable().scaledToFit().foregroundStyle(.secondary) }
    }
}

private struct AgentContextRows: View {
    @Environment(\.locale) private var locale
    let station: String
    let key: String
    var body: some View {
        let _ = locale.identifier
        TopicContent(name: "history", params: ["station": .string(station), "key": .string(key)]) { history in
            VStack(alignment: .leading, spacing: 10) {
                if history["usage"].arrayValue.isEmpty { Text(L10n.text("上下文与用量")).font(.caption).foregroundStyle(.secondary) }
                ForEach(ViewRecord.decode(history["usage"].arrayValue, key: "label")) { row in
                    LabeledContent(L10n.projected(row.value.text("label")), value: L10n.projected(row.value.text("value")))
                }
            }
        }
    }
}

private struct NodeHealthRows: View {
    @Environment(\.locale) private var locale
    let node: JSONValue
    var body: some View {
        let _ = locale.identifier
        LabeledContent(L10n.text("节点"), value: node.text("name"))
        LabeledContent(L10n.text("连接"), value: L10n.text(node.flag("online") ? "已连接" : "离线"))
        if !node["host"].objectValue.isEmpty {
            Text(L10n.projected(node["host"].text("line", fallback: node["host"].text("summary")))).font(.caption).foregroundStyle(.secondary)
            ForEach(ViewRecord.decode(node["host"]["meters"].arrayValue, key: "label")) { meter in
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent(L10n.projected(meter.value.text("label")), value: L10n.projected(meter.value.text("value")))
                    if case .number(let percent) = meter.value["percent"] {
                        ProgressView(value: max(0, min(100, percent)), total: 100).tint(meter.value.text("level") == "red" ? .red : meter.value.text("level") == "amber" ? .orange : .accentColor)
                    }
                }
            }
            Text(L10n.text(node.flag("online") ? "以上为最近一次主机采样。" : "节点离线，以上为上次采样，不代表当前状态。")).font(.caption).foregroundStyle(.secondary)
        }
        if !node["net"].objectValue.isEmpty {
            LabeledContent(L10n.text("连接路径"), value: L10n.projected(node["net"].text("path")))
            LabeledContent(L10n.text("延迟"), value: node["net"]["rtt"].text("text", fallback: L10n.text("尚未测量")))
        }
    }
}

struct SessionModelPicker: View {
    @Environment(\.locale) private var locale
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let station: String
    let key: String
    var showAccounts = false
    @State private var operation = ViewOperation()
    private var params: [String: JSONValue] { ["station": .string(station), "of": .string("session:" + key)] }
    var body: some View {
        let _ = locale.identifier
        TopicContent(name: "pick", params: params) { value in
            Form {
                if !showAccounts {
                    Section(L10n.text("模型")) {
                        ForEach(ViewRecord.decode(value["options"].arrayValue, key: "model")) { option in
                            Button { set("model", option.value["model"]) } label: {
                                HStack { Text(option.value.text("name", fallback: option.value.text("model"))); Spacer(); if option.value["model"] == value["draft"]["model"] { Image(systemName: "checkmark") } }
                            }.disabled(operation.busy)
                        }
                    }
                    if !value["efforts"].arrayValue.isEmpty {
                        Section(L10n.text("思考强度")) {
                            Button(L10n.text("默认")) { set("effort", .null) }
                            ForEach(value["efforts"].arrayValue.compactMap(\.stringValue), id: \.self) { effort in
                                Button { set("effort", .string(effort)) } label: { HStack { Text(L10n.text(effort)); Spacer(); if value["draft"].text("effort") == effort { Image(systemName: "checkmark") } } }
                            }
                        }.disabled(operation.busy)
                    }
                }
                Section(L10n.text("账号池")) {
                    Button { set("profile", .null) } label: { HStack { Text(L10n.text("自动选择")); Spacer(); if value["draft"]["profile"].stringValue == nil { Image(systemName: "checkmark") } } }
                    if !value.text("autoNote").isEmpty { Text(L10n.projected(value.text("autoNote"))).font(.caption).foregroundStyle(.secondary) }
                    ForEach(ViewRecord.decode(value["accounts"].arrayValue)) { account in
                        Button { set("profile", account.value["id"]) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(account.value.text("name"))
                                    if !account.value["quotaLine"].text("text").isEmpty { Text(L10n.projected(account.value["quotaLine"].text("text"))).font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer(); if account.value["id"] == value["draft"]["profile"] { Image(systemName: "checkmark") }
                            }
                        }.disabled(operation.busy)
                    }
                }
                if !value.text("force").isEmpty { Section { Text(L10n.projected(value.text("force"))).font(.footnote).foregroundStyle(.orange) } }
                if !value.text("dropped").isEmpty { Section { Text(L10n.projected(value.text("dropped"))).font(.footnote).foregroundStyle(.orange) } }
                Section { Button(L10n.text("保存")) { save() }.disabled(operation.busy || !value.flag("changed")) }
                OperationSection(operation: operation)
            }
        }
        .navigationTitle(L10n.text(showAccounts ? "切换账号" : "切换模型")).navigationBarTitleDisplayMode(.inline)
        .task { _ = try? await store.call("pick.set", params: params.merging(["open": .bool(true)]) { _, new in new }) }
    }
    private func set(_ field: String, _ value: JSONValue) {
        Task { await operation.run { _ = try await store.call("pick.set", params: params.merging([field: value]) { _, new in new }) } }
    }
    private func save() {
        Task { await operation.run { _ = try await store.call("pick.save", params: params); dismiss() } }
    }
}
