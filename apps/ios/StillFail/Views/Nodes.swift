import SwiftUI
import UIKit

struct NodesView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.locale) private var locale
    let workspace: String
    @State private var enrolling = false
    @State private var renaming: ViewRecord?
    @State private var removing: ViewRecord?
    @State private var confirmRemoval = false
    @State private var operation = ViewOperation()
    private var owner: WorkspaceChoice? { WorkspaceChoice.decode(store.workspaceGroups).first { $0.workspaceID == workspace && $0.accountID == store.selectedAccountID } }
    private var manage: Bool { owner?.role == "owner" || owner?.role == "admin" }
    var body: some View {
        TopicContent(name: "stations", params: ["scope": .string(workspace)]) { value in
            let rows = ViewRecord.decode(value.arrayValue)
            List {
                if rows.isEmpty { ContentUnavailableView("还没有节点", systemImage: "desktopcomputer", description: Text("在目标电脑上运行安装命令，加入这个工作区。")) .accessibilityIdentifier("nodes.empty") }
                ForEach(rows) { row in
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(row.value.text("name")).font(.headline).accessibilityIdentifier("node.name.\(row.id)")
                            Text(L10n.projected(row.value.text("summary"), language: locale.identifier).replacingOccurrences(of: "station", with: L10n.text("节点"))).font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("node.summary.\(row.id)")
                            Text(LocalizedStringKey(linkText(row.value["link"]))).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("node.link.\(row.id)")
                            if row.value["link"].text("state") == "error" { Text("连接未能建立，正在保留上次读取的数据。").font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("node.retained.\(row.id)") }
                        }
                        if !row.value["host"].objectValue.isEmpty {
                            let host = row.value["host"]
                            Text(L10n.projected(host.text("line", fallback: host.text("summary")), language: locale.identifier)).font(.subheadline).accessibilityIdentifier("node.host.\(row.id)")
                            ForEach(ViewRecord.decode(host["meters"].arrayValue, key: "label")) { meter in
                                LabeledContent(L10n.text(meter.value.text("label"), language: locale.identifier), value: L10n.projected(meter.value.text("value"), language: locale.identifier))
                                    .accessibilityIdentifier("node.metric.\(row.id).\(meter.id)")
                            }
                            Text(LocalizedStringKey(row.value.flag("online") ? "以上为最近一次主机采样。" : "节点离线，以上为上次采样，不代表当前状态。"))
                                .font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("node.sampleNote.\(row.id)")
                        }
                        if !row.value["net"].objectValue.isEmpty {
                            LabeledContent("连接路径", value: L10n.projected(row.value["net"].text("path"), language: locale.identifier)).accessibilityIdentifier("node.path.\(row.id)")
                            LabeledContent("延迟", value: row.value["net"]["rtt"].text("text", fallback: L10n.text("尚未测量"))).accessibilityIdentifier("node.latency.\(row.id)")
                        }
                        Button("重试连接") { reconnect() }.disabled(operation.busy).accessibilityIdentifier("node.retry.\(row.id)")
                        if manage {
                            Button("重命名") { renaming = row }.accessibilityIdentifier("node.rename.\(row.id)")
                            Button("移除节点", role: .destructive) { removing = row; confirmRemoval = true }.accessibilityIdentifier("node.remove.\(row.id)")
                        }
                    }
                }
                if manage { Section { Button("添加节点", systemImage: "plus") { enrolling = true }.accessibilityIdentifier("nodes.add") } }
                OperationSection(operation: operation)
            }.listStyle(.insetGrouped)
                .sheet(isPresented: $enrolling) {
                    EnrollmentView(workspace: workspace, account: owner?.accountID ?? "", existingIDs: Set(rows.map { $0.value.text("id") }))
                }
        }
        .navigationTitle("节点").navigationBarTitleDisplayMode(.large)
        .sheet(item: $renaming) { row in
            RenameSheet(title: "重命名节点", initial: row.value.text("name")) { name in
                guard let account = owner?.accountID else { throw CoreFailure(code: "not_signed_in") }
                _ = try await store.call("workspace.renameStation", params: ["workspace": .string(workspace), "account": .string(account), "station": row.value["id"], "name": .string(name)])
            }
        }
        .confirmationDialog("移除这个节点？", isPresented: $confirmRemoval, titleVisibility: .visible, presenting: removing) { row in
            Button("移除节点", role: .destructive) { remove(row) }.accessibilityIdentifier("node.remove.confirm")
            Button("取消", role: .cancel) { removing = nil }.accessibilityIdentifier("node.remove.cancel")
        } message: { _ in Text("移除后，这个工作区将无法再连接该节点。不会擦除目标电脑上的软件和本地文件。") }
        .accessibilityIdentifier("nodes.page")
    }
    private func linkText(_ value: JSONValue) -> String {
        switch value.text("state") {
        case "online": return "已连接"
        case "offline": return "离线"
        case "connecting", "reconnecting": return "正在连接…"
        case "error": return "连接异常，请重试"
        default: return "连接状态尚未确认"
        }
    }
    private func reconnect() {
        Task { await operation.run { _ = try await store.call("client.wake", params: ["network": .bool(true), "retry": .bool(true)]) } }
    }
    private func remove(_ row: ViewRecord) {
        Task { await operation.run {
            guard let account = owner?.accountID else { throw CoreFailure(code: "not_signed_in") }
            _ = try await store.call("workspace.removeStation", params: ["workspace": .string(workspace), "account": .string(account), "station": row.value["id"]])
            removing = nil
        } }
    }
}

struct EnrollmentView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    let workspace: String
    let account: String
    let existingIDs: Set<String>
    @State private var name = ""
    @State private var enrolledName = ""
    @State private var enrollment: JSONValue?
    @State private var operation = ViewOperation()
    @State private var copied = false
    var body: some View {
        let _ = locale.identifier
        NavigationStack {
            Form {
                if let enrollment {
                    Section("在目标电脑上运行") {
                        Text(enrollment.text("command")).font(.system(.body, design: .monospaced)).textSelection(.enabled).accessibilityIdentifier("enrollment.command")
                        Button(LocalizedStringKey(copied ? "已复制安装命令" : "复制安装命令"), systemImage: "doc.on.doc") { UIPasteboard.general.string = enrollment.text("command"); copied = true }.accessibilityIdentifier("enrollment.copy")
                        if let seconds = enrollment["expires_at"].intValue {
                            Text("命令有效至 \(L10n.dateTime(Date(timeIntervalSince1970: Double(seconds))))，请妥善保管。")
                                .font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("enrollment.expiry")
                        }
                        Text("安装命令包含有效期约一小时的加入凭据。复制命令并不表示节点已经加入。").font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("enrollment.security")
                    }
                    Section("加入状态") {
                        TopicContent(name: "workspace", params: ["workspace": .string(workspace)]) { value in
                            let joined = value["stations"].arrayValue.filter { !existingIDs.contains($0.text("id")) && $0.text("name") == enrolledName }
                            if joined.isEmpty {
                                Label("等待目标电脑上的节点加入…", systemImage: "clock").accessibilityIdentifier("enrollment.waiting")
                                Text("安装完成后，实际节点会出现在工作区列表中。若凭据已过期，请重新生成命令。")
                                    .font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("enrollment.waitingNote")
                            } else {
                                ForEach(ViewRecord.decode(joined)) { row in
                                    Label("工作区已收到新节点：\(row.value.text("name"))", systemImage: "checkmark.circle").accessibilityIdentifier("enrollment.joined.\(row.id)")
                                }
                                Text("连接及主机状态请在节点列表中查看。").font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("enrollment.joinedNote")
                            }
                        }
                    }
                } else {
                    Section {
                        TextField("节点名字", text: $name).accessibilityIdentifier("enrollment.name")
                        Text("请在你想运行会话的电脑上安装节点。此操作不会替你创建虚拟节点。")
                            .foregroundStyle(.secondary).accessibilityIdentifier("enrollment.note")
                    }
                }
                Button(LocalizedStringKey(enrollment == nil ? "生成安装命令" : "重新生成命令")) { generate() }
                    .disabled(operation.busy || account.isEmpty || (enrollment == nil && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                    .accessibilityIdentifier("enrollment.generate")
                OperationSection(operation: operation)
            }.navigationTitle("添加节点").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() }.accessibilityIdentifier("enrollment.done") } }
        }.interactiveDismissDisabled(operation.busy)
    }
    private func generate() {
        Task { await operation.run {
            let chosenName = enrollment == nil ? name.trimmingCharacters(in: .whitespacesAndNewlines) : enrolledName
            let result = try await store.call("workspace.enroll", params: ["workspace": .string(workspace), "account": .string(account), "name": .string(chosenName)])
            guard !result.text("command").isEmpty, result["expires_at"].intValue != nil else { throw CoreFailure(code: "invalid_response") }
            enrollment = result; enrolledName = chosenName; copied = false
        } }
    }
}
