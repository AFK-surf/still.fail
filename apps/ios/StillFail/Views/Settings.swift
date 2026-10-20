import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage(L10n.preferenceKey) private var appLanguage = "system"
    @State private var rename = false
    @State private var choosingWorkspace = false
    @State private var addAccount = false
    @State private var signOutConfirmation = false
    @State private var operation = ViewOperation()
    private var account: JSONValue? { store.accounts.first { $0.text("sub") == store.selectedAccountID } ?? (store.selectedAccountID == nil ? store.accounts.first : nil) }
    private var current: WorkspaceChoice? { WorkspaceChoice.decode(store.workspaceGroups).first { $0.workspaceID == store.selectedWorkspaceID && $0.accountID == store.selectedAccountID } }
    var body: some View {
        Form {
            Section("账号") {
                if let account {
                    NavigationLink { AccountView(account: account.text("sub")) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(account.text("name", fallback: account.text("email"))).accessibilityIdentifier("settings.account.name")
                            Text(account.text("email")).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("settings.account.email")
                        }
                    }.accessibilityIdentifier("settings.account")
                }
                ForEach(ViewRecord.decode(store.accounts, key: "sub")) { row in
                    Button {
                        guard !operation.busy else { return }
                        Task { await operation.run { try store.switchAccount(account: row.value.text("sub")) } }
                    } label: {
                        HStack {
                            Text(row.value.text("email", fallback: row.value.text("name"))).foregroundStyle(.primary)
                            Spacer()
                            if row.value.text("sub") == store.selectedAccountID { Image(systemName: "checkmark").accessibilityLabel("当前账号") }
                        }
                    }.accessibilityIdentifier("settings.switchAccount.\(row.id)")
                }
                Button("添加账号", systemImage: "person.badge.plus") { addAccount = true }.accessibilityIdentifier("settings.addAccount")
            }
            Section("工作区") {
                Button("切换工作区") { choosingWorkspace = true }.accessibilityIdentifier("settings.workspaces")
                if let current {
                    LabeledContent("名字", value: current.name).accessibilityIdentifier("settings.workspace.name")
                    LabeledContent("你的权限", value: L10n.text(current.role == "owner" ? "所有者" : current.role == "admin" ? "管理员" : "成员")).accessibilityIdentifier("settings.workspace.role")
                    if current.role == "owner" || current.role == "admin" {
                        Button("重命名工作区") { rename = true }.accessibilityIdentifier("settings.workspace.rename")
                    }
                }
            }
            Section("外观") {
                Picker("外观", selection: $appearance) {
                    Text("跟随系统").tag("system").accessibilityIdentifier("appearance.system")
                    Text("浅色").tag("light").accessibilityIdentifier("appearance.light")
                    Text("深色").tag("dark").accessibilityIdentifier("appearance.dark")
                }.accessibilityIdentifier("settings.appearance")
            }
            Section("语言") {
                Picker("应用语言", selection: $appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(verbatim: language.nativeName).tag(language.rawValue)
                    }
                }.accessibilityIdentifier("settings.language")
                Text("语言更改立即生效。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let account {
                Section {
                    Button("退出当前账号", role: .destructive) { signOutConfirmation = true }.disabled(operation.busy).accessibilityIdentifier("settings.signOut")
                    NavigationLink("删除当前账号") { AccountDeletionView(account: account.text("sub")) }.accessibilityIdentifier("settings.deleteAccount")
                }
            }
            OperationSection(operation: operation)
        }.navigationTitle("设置").navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $choosingWorkspace) { NavigationStack { WorkspaceChooserView() } }
            .sheet(isPresented: $addAccount) { NavigationStack { LoginView(addingAccount: true) } }
            .sheet(isPresented: $rename) {
                if let current {
                    RenameSheet(title: "重命名工作区", initial: current.name) { name in
                        _ = try await store.call("workspace.rename", params: ["account": .string(current.accountID), "workspace": .string(current.workspaceID), "name": .string(name)])
                    }
                }
            }
            .confirmationDialog("退出当前账号？", isPresented: $signOutConfirmation, titleVisibility: .visible) {
                Button("退出登录", role: .destructive) {
                    if let id = account?.text("sub") { Task { await operation.run { try await store.signOut(account: id) } } }
                }.accessibilityIdentifier("settings.signOut.confirm")
                Button("取消", role: .cancel) {}.accessibilityIdentifier("settings.signOut.cancel")
            } message: { Text("只退出这台设备上的当前账号，其他账号不受影响。") }
            .task { _ = try? await store.call("client.focus", params: ["chat": .null]) }
            .accessibilityIdentifier("settings.page")
    }
}

struct AccountView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.locale) private var locale
    let account: String
    @State private var revoking: ViewRecord?
    @State private var confirmation = false
    @State private var operation = ViewOperation()
    var body: some View {
        let _ = locale.identifier
        TopicContent(name: "loginSessions", params: ["account": .string(account)]) { value in
            List {
                Section("账号资料") {
                    if let identity = store.accounts.first(where: { $0.text("sub") == account }) {
                        LabeledContent("名字", value: identity.text("name")).accessibilityIdentifier("account.name")
                        LabeledContent("邮箱", value: identity.text("email")).accessibilityIdentifier("account.email")
                        if !identity.text("provider").isEmpty { LabeledContent("登录方式", value: identity.text("provider")).accessibilityIdentifier("account.provider") }
                    }
                }
                Section("登录的设备") {
                    if value.arrayValue.isEmpty { ContentUnavailableView("暂无设备记录", systemImage: "iphone").accessibilityIdentifier("account.devices.empty") }
                    ForEach(ViewRecord.decode(value.arrayValue)) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(row.value.text("name", fallback: L10n.text("设备"))).font(.headline).accessibilityIdentifier("account.device.name.\(row.id)")
                            if row.value.flag("current") { Text("当前设备").font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("account.device.current.\(row.id)") }
                            if let seconds = row.value["created_at"].intValue {
                                Text("登录于 \(L10n.dateTime(Date(timeIntervalSince1970: Double(seconds))))").font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("account.device.date.\(row.id)")
                            }
                            if !row.value.flag("current") {
                                Button("让这台设备退出", role: .destructive) { revoking = row; confirmation = true }.disabled(operation.busy).accessibilityIdentifier("account.device.revoke.\(row.id)")
                            }
                        }
                    }
                }
                OperationSection(operation: operation)
            }.listStyle(.insetGrouped)
        }.navigationTitle("账号与设备").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("让这台设备退出？", isPresented: $confirmation, titleVisibility: .visible, presenting: revoking) { row in
                Button("退出设备", role: .destructive) { Task { await operation.run { _ = try await store.call("loginSession.revoke", params: ["account": .string(account), "id": row.value["id"]]); revoking = nil } } }.accessibilityIdentifier("account.device.revoke.confirm")
                Button("取消", role: .cancel) { revoking = nil }.accessibilityIdentifier("account.device.revoke.cancel")
            } message: { row in Text("将撤销「\(row.value.text("name", fallback: L10n.text("这台设备")))」的登录会话。") }
            .accessibilityIdentifier("account.page")
    }
}

/// Coverage and final destructive actions remain locked at this implementation stage.
/// Backend flags alone are not product approval and cannot unlock this view.
struct AccountDeletionView: View {
    @Environment(AppStore.self) private var store
    let account: String
    @State private var summary: JSONValue?
    @State private var operation = ViewOperation()
    // This is an unconditional implementation lock, not a server-controlled capability.
    static let finalDeletionLocked = true
    enum Copy {
        static let lockedTitle = "暂时无法删除账号"
        static let lockedExplanation = "删除的数据范围和保留期限尚未核实，暂不能提交删除请求。"
        static let proposalHeading = "删除方案（尚未实现或验证）"
        static let accountPlan = "你的个人资料、登录身份、个人偏好和工作区成员关系会被删除，服务会撤销这个账号的登录和访问权限。"
        static let proposalNote = "以下仅说明拟实施的删除范围，不代表已提交请求或已完成删除。"
        static let computerBoundary = "这不会清空电脑，也不会删除与这个账号无关的文件。"
        static let offlineHeading = "拟定访问规则（尚待验证）"
        static let offlinePolicy = "未连接服务的电脑可能仍接受旧凭据访问，最长30天。它重新连接后会收到撤销通知。这个访问期限不代表电脑上的相关内容会在30天内自动清除。"
        static let offlineGrantNote = "上述访问期限从原始授权签发时起算，撤销通知和相关内容清理仍待实现或验证。"
        static let summaryUnavailable = "暂时无法读取账号状态。请检查网络后重试。"
    }
    var body: some View {
        Form {
            Section {
                Text(LocalizedStringKey(Copy.lockedExplanation)).accessibilityIdentifier("deletion.locked")
            }
            Section(LocalizedStringKey(Copy.proposalHeading)) {
                Text(LocalizedStringKey(Copy.proposalNote)).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("deletion.proposalNote")
                Text(LocalizedStringKey(Copy.accountPlan)).accessibilityIdentifier("deletion.explanation")
                Text("这台设备上的其他账号不受影响。").accessibilityIdentifier("deletion.otherAccounts")
                Text("这不会删除你的 Apple 或 Google 账号。").accessibilityIdentifier("deletion.providerBoundary")
            }
            Section("拟定数据边界（尚待核实）") {
                Text(LocalizedStringKey(Copy.computerBoundary)).accessibilityIdentifier("deletion.preservation")
                Text("以下项目均为待实现或验证的方案。日志、遥测和备份的实际保留期限尚未核实。").font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("deletion.coverageNote")
                if let summary {
                    ForEach(ViewRecord.decode(summary["categories"].arrayValue)) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(row.value.text("detail")).accessibilityIdentifier("deletion.category.\(row.id)")
                            Text("核实状态：\(Text(LocalizedStringKey(coverageState(row.value.text("status")))))").font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("deletion.category.status.\(row.id)")
                        }
                    }
                    if !summary.text("sharedPreservation").isEmpty { Text(summary.text("sharedPreservation")).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("deletion.sharedPreservation") }
                } else if !operation.busy { Text("删除范围尚未确认，请读取服务端摘要。").foregroundStyle(.secondary).accessibilityIdentifier("deletion.coverageUnknown") }
            }
            Section(LocalizedStringKey(Copy.offlineHeading)) {
                Text(LocalizedStringKey(Copy.offlinePolicy)).accessibilityIdentifier("deletion.offlinePolicy")
                Text(LocalizedStringKey(Copy.offlineGrantNote)).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("deletion.offlineGrantNote")
            }
            if let summary {
                if !summary["lastOwnerWorkspaces"].arrayValue.isEmpty {
                    Section("请先处理你拥有的工作区") {
                        ForEach(ViewRecord.decode(summary["lastOwnerWorkspaces"].arrayValue)) { row in
                            NavigationLink(row.value.text("name")) {
                                OwnershipResolutionView(account: account, workspace: row.value.text("id"), name: row.value.text("name"))
                            }.accessibilityIdentifier("deletion.ownerWorkspace.\(row.id)")
                        }
                    }
                }
                if summary.flag("reauthNeeded") {
                    Section("重新验证") {
                        Text("删除前需要使用当前账号的原登录方式重新验证。当前版本尚未完成安全重新验证流程，不能继续删除。")
                            .foregroundStyle(.secondary).accessibilityIdentifier("deletion.reauthUnavailable")
                    }
                }
                if !summary["blockers"].arrayValue.isEmpty {
                    Section("尚未满足的条件") {
                        ForEach(ViewRecord.decode(summary["blockers"].arrayValue, key: "code")) { row in Text(LocalizedStringKey(blockerText(row.value.text("code")))).accessibilityIdentifier("deletion.blocker.\(row.id)") }
                    }
                }
            }
            Section {
                Button("删除当前账号", role: .destructive) {}.disabled(Self.finalDeletionLocked).accessibilityIdentifier("deletion.confirm.locked")
                Button("重新查看账号状态") { readSummary() }.disabled(operation.busy).accessibilityIdentifier("deletion.refresh")
                OperationSection(operation: operation)
            }
        }.navigationTitle(LocalizedStringKey(Copy.lockedTitle)).navigationBarTitleDisplayMode(.inline)
            .task { if summary == nil { readSummary() } }.accessibilityIdentifier("deletion.page")
    }
    private func readSummary() {
        Task { await operation.run {
            let value = try await store.call("auth.deletionSummary", params: ["account": .string(account)])
            guard value.text("account") == account else { throw CoreFailure(code: "account_mismatch", message: "这不是要删除的账号。请使用当前账号重新验证。") }
            summary = value
        }
        if let code = operation.code, ["timeout_uncertain", "core_restarted", "cancelled_uncertain"].contains(code) {
            operation.error = Copy.summaryUnavailable
        }
        }
    }
    private func coverageState(_ status: String) -> String {
        switch status { case "planned": return "尚待实现或验证"; case "unverified", "proposed_unverified": return "未验证"; case "unimplemented": return "未实现"; default: return "尚未核实，不能提交删除请求" }
    }
    private func blockerText(_ code: String) -> String {
        switch code { case "last_owner": return "你仍是某些工作区的最后一位所有者。"; case "reauth_required": return "需要安全重新验证当前账号。"; case "coverage_incomplete": return "个人数据和共享记录的处理范围尚未完整验证。"; default: return "服务端仍有未满足的删除条件，请重新查看账号状态。" }
    }
}

struct OwnershipResolutionView: View {
    @Environment(AppStore.self) private var store
    let account: String
    let workspace: String
    let name: String
    @State private var chosenMember = ""
    @State private var confirmingTransfer = false
    @State private var workspaceDelete = false
    @State private var operation = ViewOperation()
    var body: some View {
        TopicContent(name: "workspace", params: ["workspace": .string(workspace)]) { value in
            let members = value["members"].arrayValue.filter { $0.text("sub") != account }
            Form {
                Section("请先处理你拥有的工作区") {
                    Text(name).font(.headline).accessibilityIdentifier("ownership.workspaceName")
                    Text("不会自动转移所有权，也不会把工作区删除混入账号删除。").foregroundStyle(.secondary).accessibilityIdentifier("ownership.note")
                    if members.isEmpty {
                        Text("没有其他成员可以接任。删除工作区需要单独确认，但当前阶段最终删除仍锁定。").accessibilityIdentifier("ownership.noMembers")
                    } else {
                        Picker("新的所有者", selection: $chosenMember) {
                            Text("请选择现有成员").tag("")
                            ForEach(ViewRecord.decode(members, key: "sub")) { row in Text(row.value.text("name", fallback: row.value.text("email"))).tag(row.value.text("sub")) }
                        }.accessibilityIdentifier("ownership.member")
                        Button("授予所有者权限") { confirmingTransfer = true }.disabled(chosenMember.isEmpty || operation.busy || value.text("role") != "owner").accessibilityIdentifier("ownership.transfer")
                        Text("你仍保留现有权限。授予另一位成员所有者权限后，请返回重新读取账号删除摘要。").font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("ownership.transferNote")
                    }
                    Button("查看单独删除工作区的说明", role: .destructive) { workspaceDelete = true }.accessibilityIdentifier("ownership.workspaceDeleteInfo")
                    OperationSection(operation: operation)
                }
            }
        }.navigationTitle("工作区所有权").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("授予这位成员所有者权限？", isPresented: $confirmingTransfer, titleVisibility: .visible) {
                Button("确认授予") { Task { await operation.run { _ = try await store.call("workspace.setRole", params: ["account": .string(account), "workspace": .string(workspace), "member": .string(chosenMember), "role": .string("owner")]); chosenMember = "" } } }.accessibilityIdentifier("ownership.transfer.confirm")
                Button("取消", role: .cancel) {}.accessibilityIdentifier("ownership.transfer.cancel")
            } message: { Text("新的所有者将能管理成员、节点及工作区。") }
            .sheet(isPresented: $workspaceDelete) { LockedWorkspaceDeletionView(name: name) }
            .accessibilityIdentifier("ownership.page")
    }
}

struct LockedWorkspaceDeletionView: View {
    @Environment(\.dismiss) private var dismiss
    let name: String
    var body: some View {
        NavigationStack {
            Form {
                Section("单独删除工作区？") {
                    Text("「\(name)」的删除是独立操作，不等同于删除账号。其他成员也会受到影响，必须单独确认处理范围。")
                        .accessibilityIdentifier("workspaceDeletion.explanation")
                    Text(LocalizedStringKey(AccountDeletionView.Copy.lockedExplanation))
                        .foregroundStyle(.secondary).accessibilityIdentifier("workspaceDeletion.locked")
                    Button("删除工作区", role: .destructive) {}.disabled(true).accessibilityIdentifier("workspaceDeletion.confirm.locked")
                }
            }.navigationTitle("删除工作区").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.accessibilityIdentifier("workspaceDeletion.cancel") } }
        }
    }
}
