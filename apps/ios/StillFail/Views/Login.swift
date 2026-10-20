import SwiftUI
import AuthenticationServices

/// Stage-specific safe copy; provider details and error codes never become UI text.
enum LoginCopy {
    static let appleUnavailable = "Apple 登录暂时不可用。请重试。"
    static func completion(provider: String, error: Error) -> String? {
        let code = (error as? CoreFailure)?.code
        if code == "auth_cancelled" { return nil }
        if ["login_expired", "invalid_grant"].contains(code ?? "") { return "这次登录已过期。请重新登录。" }
        if ["login_state_mismatch", "auth_invalid_callback", "auth_invalid_url"].contains(code ?? "") { return "未能完成登录。请重新登录。" }
        return provider == "apple" ? "未能通过 Apple 登录。请重试。" : "未能用 Google 登录。请重试。"
    }
}

struct LoginView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @State private var attempt: JSONValue?
    @State private var preparing = false
    @State private var appleError: String?
    @State private var completing = false
    @State private var appleAuthorizing = false
    @State private var googleContentHeight: CGFloat = 0
    @ScaledMetric(relativeTo: .body) private var scaledButtonHeight: CGFloat = 52
    var addingAccount = false

    private var providerButtonHeight: CGFloat { max(52, scaledButtonHeight, googleContentHeight) }
    private var authenticationBusy: Bool { appleAuthorizing || completing || store.isAuthenticating }
    private var supportingTextColor: Color {
        colorScheme == .dark
            ? Color(red: 174 / 255, green: 174 / 255, blue: 178 / 255)
            : Color(red: 107 / 255, green: 107 / 255, blue: 112 / 255)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("still.fail")
                    .font(.title3.weight(.semibold))
                    .accessibilityIdentifier("login.brand")
                VStack(alignment: .leading, spacing: 16) {
                    Text(LocalizedStringKey(addingAccount ? "添加账号" : "在手机上跟进助手的工作"))
                        .font(.largeTitle.bold())
                        .accessibilityIdentifier("login.title")
                    Text("登录后，查看工作区里的会话和节点，需要你决定时及时回复。")
                        .font(.body)
                        .foregroundStyle(supportingTextColor)
                        .accessibilityIdentifier("login.explanation")
                }.fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 16) {
                    providerButtons
                    VStack(alignment: .leading, spacing: 8) {
                        Text("之前用 Google 登录？请继续使用原来的 Google 账号。")
                            .accessibilityIdentifier("login.accountNote")
                        Text("Apple 与 Google 账号不会自动合并。")
                            .accessibilityIdentifier("login.accountSeparation")
                    }
                    .font(.subheadline)
                    .foregroundStyle(supportingTextColor)
                    .fixedSize(horizontal: false, vertical: true)
                }
                if authenticationBusy { ProgressView("正在登录…").accessibilityIdentifier("login.loading") }
                else if preparing { ProgressView("正在准备 Apple 登录…").accessibilityIdentifier("login.preparing") }
                if let error = appleError {
                    providerNotice(message: error, retry: { Task { await prepareApple() } })
                }
                if let error = store.authError { providerNotice(message: error) }
            }.padding(24).frame(maxWidth: 520, alignment: .leading).frame(maxWidth: .infinity)
        }.background(Color(uiColor: .systemBackground))
            .onPreferenceChange(LoginGoogleHeightKey.self) { googleContentHeight = $0 }
            .task { await prepareApple() }
            .navigationTitle(LocalizedStringKey(addingAccount ? "添加账号" : ""))
            .accessibilityIdentifier("login.page")
    }

    private var providerButtons: some View {
        VStack(spacing: 12) {
            SignInWithAppleButton(.signIn, onRequest: { request in
                appleAuthorizing = true
                request.requestedScopes = [.fullName, .email]
                request.nonce = attempt?.text("nonce")
                request.state = attempt?.text("state")
            }, onCompletion: completeApple)
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            // The native button style is chosen at creation; recreate only the control on appearance changes.
            .id(colorScheme)
            .cornerRadius(12)
            .frame(maxWidth: .infinity)
            .frame(height: providerButtonHeight)
            .disabled(attempt == nil || authenticationBusy)
            .accessibilityIdentifier("login.apple")
            Button {
                guard !authenticationBusy else { return }
                Task { await store.signInWithGoogle() }
            } label: {
                HStack(spacing: 12) {
                    Image("GoogleG").resizable().scaledToFit().frame(width: 20, height: 20).accessibilityHidden(true)
                    Text("用 Google 登录").font(.body.weight(.medium))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
                // Measure the wrapped label before applying the shared button height.
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: LoginGoogleHeightKey.self, value: geometry.size.height)
                    }
                }
                .frame(height: providerButtonHeight)
                .contentShape(RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain)
                .foregroundStyle(Color.black)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(red: 116 / 255, green: 119 / 255, blue: 117 / 255), lineWidth: 1))
                .disabled(authenticationBusy)
                .accessibilityIdentifier("login.google")
        }
    }

    private func providerNotice(message: String, retry: (() -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(message))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("operation.error.message")
            if let retry {
                Button(action: retry) {
                    Text("重试").frame(minWidth: 44, minHeight: 44)
                }
                .disabled(preparing || authenticationBusy)
                .accessibilityIdentifier("operation.retry")
            }
        }.font(.subheadline).padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground))
            .accessibilityElement(children: .contain)
    }

    private func prepareApple(clearError: Bool = true) async {
        guard !preparing else { return }
        preparing = true; attempt = nil
        if clearError { appleError = nil }
        defer { preparing = false }
        do {
            let value = try await store.call("auth.appleBegin")
            guard !value.text("attempt").isEmpty, !value.text("nonce").isEmpty, !value.text("state").isEmpty else {
                appleError = LoginCopy.appleUnavailable; return
            }
            attempt = value
        } catch { if appleError == nil { appleError = LoginCopy.appleUnavailable } }
    }
    private func completeApple(_ result: Result<ASAuthorization, Error>) {
        appleAuthorizing = false
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled { appleError = "未能通过 Apple 登录。请重试。" }
            else { appleError = nil }
            Task { await prepareApple(clearError: false) }
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken, let token = String(data: tokenData, encoding: .utf8),
                  let codeData = credential.authorizationCode, let code = String(data: codeData, encoding: .utf8),
                  let attemptID = attempt?["attempt"].stringValue else {
                appleError = "未能完成登录。请重新登录。"
                Task { await prepareApple(clearError: false) }
                return
            }
            guard let expectedState = attempt?["state"].stringValue,
                  credential.state == expectedState else {
                appleError = "未能完成登录。请重新登录。"
                attempt = nil
                Task { await prepareApple(clearError: false) }
                return
            }
            var params: [String: JSONValue] = ["attempt": .string(attemptID), "identityToken": .string(token), "authorizationCode": .string(code), "state": .string(expectedState)]
            if let name = credential.fullName {
                let formatted = PersonNameComponentsFormatter().string(from: name)
                if !formatted.isEmpty { params["name"] = .string(formatted) }
            }
            completing = true
            Task {
                do {
                    _ = try await store.call("auth.appleComplete", params: params)
                    completing = false; attempt = nil
                } catch {
                    appleError = LoginCopy.completion(provider: "apple", error: error)
                    completing = false; attempt = nil
                    await prepareApple(clearError: false)
                }
            }
        }
    }
}

private struct LoginGoogleHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
