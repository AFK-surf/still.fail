import SwiftUI

struct WorkspaceChooserView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var operation = ViewOperation()
    @State private var creating = false
    @State private var addingAccount = false
    var body: some View {
        List {
            if store.workspaceGroups.isEmpty {
                ProgressView("正在读取工作区…")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            ForEach(ViewRecord.decode(store.workspaceGroups, key: "account")) { record in
                let group = record.value
                let account = group["account"].text("sub")
                Section {
                    if let message = group["error"]["message"].stringValue {
                        FailureNotice(message: L10n.text("这个账号的工作区尚未读取成功。"), retry: retryWorkspaces)
                            .accessibilityHint(L10n.text(message.isEmpty ? "请重试" : "尚未确认最新状态"))
                    } else if !group.flag("loaded") {
                        ProgressView("正在读取工作区…").accessibilityIdentifier("workspace.loading.\(account)")
                    }
                    ForEach(WorkspaceChoice.decode([group])) { choice in
                        Button {
                            Task { await operation.run {
                                try store.switchWorkspace(workspace: choice.workspaceID, account: choice.accountID)
                                dismiss()
                            } }
                        } label: {
                            HStack(spacing: 12) {
                                Text(String(choice.name.prefix(1)).uppercased())
                                    .font(.headline).foregroundStyle(Color.accentColor)
                                    .frame(width: 38, height: 38)
                                    .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(choice.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                        .lineLimit(1).accessibilityIdentifier("workspace.name.\(choice.id)")
                                    HStack(spacing: 10) {
                                        Label(L10n.format("%lld 个节点", choice.value["stations"].intValue ?? 0), systemImage: "desktopcomputer")
                                        Label(L10n.format("%lld 人", choice.value["members"].intValue ?? 0), systemImage: "person.2")
                                    }.font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if store.selectedWorkspaceID == choice.workspaceID && store.selectedAccountID == choice.accountID {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                                        .accessibilityLabel("当前工作区")
                                }
                            }.padding(.vertical, 3).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(operation.busy).accessibilityIdentifier("workspace.select.\(choice.id)")
                            .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
                    }
                    ForEach(ViewRecord.decode(group["invitations"].arrayValue, prefix: account + ":")) { invite in
                        VStack(alignment: .leading, spacing: 8) {
                            Label(L10n.format("%@ 邀请你加入「%@」", invite.value.text("inviter", fallback: L10n.text("团队")), invite.value.text("name")), systemImage: "envelope.badge")
                                .font(.subheadline)
                                .accessibilityIdentifier("invitation.name.\(invite.id)")
                            HStack {
                                Button("加入") { respond(invite.value, account: account, accept: true) }.accessibilityIdentifier("invitation.accept.\(invite.id)")
                                Button("忽略", role: .cancel) { respond(invite.value, account: account, accept: false) }.accessibilityIdentifier("invitation.decline.\(invite.id)")
                            }.buttonStyle(.borderless).disabled(operation.busy)
                        }
                    }
                    if group.flag("loaded") && group["workspaces"].arrayValue.isEmpty && group["invitations"].arrayValue.isEmpty {
                        Text("还没有工作区。你可以接受团队邀请，或按账号权限新建工作区。")
                            .foregroundStyle(.secondary).accessibilityIdentifier("workspace.empty.\(account)")
                    }
                } header: {
                    HStack(spacing: 6) {
                        Image(systemName: "person.crop.circle")
                        Text(group["account"].text("email", fallback: group["account"].text("name")))
                            .lineLimit(1).textCase(nil)
                    }.accessibilityIdentifier("workspace.account.\(account)")
                }
            }
            if operation.busy || operation.error != nil {
                Section { OperationSection(operation: operation) }
            }
            Section {
                Button { creating = true } label: {
                    Label("新建工作区", systemImage: "plus.rectangle.on.rectangle")
                }.accessibilityIdentifier("workspace.create")
                Button { addingAccount = true } label: {
                    Label("添加账号", systemImage: "person.crop.circle.badge.plus")
                }.accessibilityIdentifier("workspace.addAccount")
            }.disabled(operation.busy)
        }.listStyle(.insetGrouped)
            .contentMargins(.top, 8, for: .scrollContent)
            .navigationTitle("工作区").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if store.selectedWorkspaceID != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("关闭", systemImage: "xmark") { dismiss() }
                            .accessibilityIdentifier("workspace.close")
                    }
                }
            }
            .sheet(isPresented: $creating) { CreateWorkspaceView() }
            .sheet(isPresented: $addingAccount) { NavigationStack { LoginView(addingAccount: true) } }
            .accessibilityIdentifier("workspace.page")
    }
    private func retryWorkspaces() {
        Task { await operation.run {
            _ = try await store.call("client.wake", params: ["away": .number(0), "network": .bool(true), "retry": .bool(true)])
        } }
    }
    private func respond(_ invite: JSONValue, account: String, accept: Bool) {
        Task { await operation.run {
            let value = try await store.call(accept ? "invitation.accept" : "invitation.decline", params: ["account": .string(account), "id": invite["id"]])
            if accept, let id = value["id"].stringValue {
                try store.switchWorkspace(workspace: id, account: account)
                dismiss()
            }
        } }
    }
}

struct CreateWorkspaceView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var account = ""
    @State private var code = ""
    @State private var operation = ViewOperation()
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("工作区是一组人和他们共用的节点。你会成为它的所有者。")
                        .foregroundStyle(.secondary).accessibilityIdentifier("workspace.create.note")
                    TextField("工作区名字", text: $name).accessibilityIdentifier("workspace.create.name")
                    Picker("属于哪个账号", selection: $account) {
                        ForEach(ViewRecord.decode(store.accounts, key: "sub")) { row in
                            Text(row.value.text("email", fallback: row.value.text("name"))).tag(row.value.text("sub"))
                        }
                    }.accessibilityIdentifier("workspace.create.account")
                }
                Section("邀请码") {
                    TextField("如账号需要，请填写邀请码", text: $code).textInputAutocapitalization(.characters).autocorrectionDisabled().accessibilityIdentifier("workspace.create.code")
                    Text("still.fail 目前只对受邀的人开放。新建权限由服务端确认；接受团队邀请不需要邀请码。")
                        .font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("workspace.create.permission")
                }
                OperationSection(operation: operation)
            }.navigationTitle("新建工作区").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.accessibilityIdentifier("workspace.create.cancel") }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("新建") { create() }.disabled(account.isEmpty || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || operation.busy)
                            .accessibilityIdentifier("workspace.create.submit")
                    }
                }
        }.onAppear { account = store.selectedAccountID ?? store.accounts.first?.text("sub") ?? "" }
            .interactiveDismissDisabled(operation.busy)
    }
    private func create() {
        Task { await operation.run {
            var params: [String: JSONValue] = ["account": .string(account), "name": .string(name.trimmingCharacters(in: .whitespacesAndNewlines))]
            if !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { params["invite_code"] = .string(code.trimmingCharacters(in: .whitespacesAndNewlines)) }
            let value = try await store.call("workspace.create", params: params)
            if let id = value["id"].stringValue {
                try store.switchWorkspace(workspace: id, account: account)
            }
            dismiss()
        } }
    }
}
