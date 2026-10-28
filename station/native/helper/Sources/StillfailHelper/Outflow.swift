// Data outflow (docs/data-outflow.md): who a program at the other end of the station's outflow socket is, by the audit
// token the station took of it as it connected (its code signature as macOS checks it now), and the window that asks
// the person at this Mac whether it may read their data: the details first, with each kind of data to take out, then
// a summary confirmed with Touch ID or the Mac's password.
import AppKit
import LocalAuthentication
import Security
import SwiftUI

enum Outflow {
  /// The program with audit token `hex` (32 bytes): its path, whether its signature holds, its Team ID, signing
  /// identifier, the signing certificate's name and the app it is in. An error when it is gone.
  static func identify(_ hex: String) -> [String: Any] {
    guard let token = bytes(hex), token.count == 32 else { return ["error": "no audit token"] }
    var code: SecCode?
    guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributeAudit: token] as CFDictionary, [], &code) == errSecSuccess, let code else {
      return ["error": "the program is gone"]
    }
    var staticCode: SecStaticCode?
    SecCodeCopyStaticCode(code, [], &staticCode)
    var url: CFURL?
    var info: CFDictionary?
    if let staticCode {
      SecCodeCopyPath(staticCode, [], &url)
      SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
    }
    let signing = info as? [String: Any] ?? [:]
    let path = (url as URL?)?.path ?? ""
    let certificates = signing[kSecCodeInfoCertificates as String] as? [SecCertificate] ?? []
    let signer = certificates.first.flatMap { SecCertificateCopySubjectSummary($0) as String? }
    // macOS's own programs carry no Team ID: Apple's anchor says they are Apple's.
    var apple: SecRequirement?
    let byApple = SecRequirementCreateWithString("anchor apple" as CFString, [], &apple) == errSecSuccess && apple.map { SecCodeCheckValidity(code, [], $0) == errSecSuccess } == true
    return [
      "path": path,
      "valid": SecCodeCheckValidity(code, [], nil) == errSecSuccess,
      "teamId": signing[kSecCodeInfoTeamIdentifier as String] as? String ?? (byApple ? "Apple" : NSNull()),
      "identifier": signing[kSecCodeInfoIdentifier as String] as? String ?? NSNull(),
      "signer": signer ?? NSNull(),
      "app": app(path) ?? NSNull(),
    ]
  }

  /// The name of the app `path` is in (the outermost `.app` above it), as its bundle says it.
  static func app(_ path: String) -> String? {
    let parts = path.split(separator: "/", omittingEmptySubsequences: false)
    guard let at = parts.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
    let bundle = parts[...at].joined(separator: "/")
    let infos = Bundle(path: bundle)?.infoDictionary
    return (infos?["CFBundleDisplayName"] as? String) ?? (infos?["CFBundleName"] as? String) ?? String(parts[at].dropLast(4))
  }

  static func bytes(_ hex: String) -> Data? {
    guard hex.count % 2 == 0 else { return nil }
    var out = Data()
    var at = hex.startIndex
    while at < hex.endIndex {
      let next = hex.index(at, offsetBy: 2)
      guard let byte = UInt8(hex[at..<next], radix: 16) else { return nil }
      out.append(byte)
      at = next
    }
    return out
  }
}

/// The asking window: one at a time; another ask while it is up is refused (`busy`).
@MainActor
final class OutflowWindow {
  static let shared = OutflowWindow()
  private var windowController: NSWindowController?
  private var answer: (([String: Any]) -> Void)?
  private let delegate = OutflowDelegate()
  private var timer: Timer?

  /// Asks `request` (`words`, `identity`, `scopes`, `ms`): answered once with `{answer: "allow", scopes}` or
  /// `{answer: "refuse"}` (refused, closed, or not answered within `ms`).
  func ask(_ request: [String: Any], answer: @escaping ([String: Any]) -> Void) {
    if windowController != nil {
      answer(["answer": "refuse", "busy": true])
      return
    }
    self.answer = answer
    let model = OutflowModel(request: request)
    model.done = { [weak self] scopes in self?.finish(scopes.map { ["answer": "allow", "scopes": $0] } ?? ["answer": "refuse"]) }
    let host = NSHostingController(rootView: OutflowView(model: model))
    let window = NSWindow(contentViewController: host)
    window.title = model.word("title", "still.fail")
    window.styleMask = [.titled, .closable, .fullSizeContentView]
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isMovableByWindowBackground = true
    window.isReleasedWhenClosed = false
    window.level = .floating
    window.center()
    delegate.closed = { [weak self] in self?.finish(["answer": "refuse"]) }
    window.delegate = delegate
    let controller = NSWindowController(window: window)
    windowController = controller
    _ = NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    controller.showWindow(nil)
    let ms = (request["ms"] as? Double) ?? 600_000
    timer = Timer.scheduledTimer(withTimeInterval: ms / 1000, repeats: false) { [weak self] _ in
      MainActor.assumeIsolated { self?.finish(["answer": "refuse", "late": true]) }
    }
  }

  /// The program that asked is gone: refused, the window closed.
  func cancel() {
    finish(["answer": "refuse", "left": true])
  }

  private func finish(_ result: [String: Any]) {
    guard let answer else { return }
    self.answer = nil
    timer?.invalidate()
    timer = nil
    let controller = windowController
    windowController = nil
    controller?.window?.delegate = nil
    controller?.close()
    DispatchQueue.main.async { _ = NSApp.setActivationPolicy(.accessory) }
    answer(result)
  }
}

private final class OutflowDelegate: NSObject, NSWindowDelegate {
  var closed: (() -> Void)?
  func windowWillClose(_: Notification) {
    closed?()
  }
}

@MainActor
final class OutflowModel: ObservableObject {
  struct Scope: Identifiable {
    let id: String
    let name: String
    let why: String
  }

  let words: [String: String]
  let identity: [String: Any]
  let scopes: [Scope]
  @Published var chosen: Set<String>
  @Published var confirming = false
  @Published var failed: String?
  var done: (([String]?) -> Void)?

  init(request: [String: Any]) {
    words = (request["words"] as? [String: Any] ?? [:]).compactMapValues { $0 as? String }
    identity = request["identity"] as? [String: Any] ?? [:]
    let asked = request["scopes"] as? [[String: Any]] ?? []
    scopes = asked.compactMap { s in
      guard let id = s["id"] as? String else { return nil }
      return Scope(id: id, name: s["name"] as? String ?? id, why: s["why"] as? String ?? "")
    }
    chosen = Set(scopes.map(\.id))
  }

  func word(_ key: String, _ otherwise: String) -> String {
    words[key].flatMap { $0.isEmpty ? nil : $0 } ?? otherwise
  }

  func text(_ key: String) -> String? {
    identity[key] as? String
  }

  var signed: Bool { text("teamId") != nil && identity["valid"] as? Bool == true }

  /// The second step: the summary, confirmed as the Mac's owner (Touch ID, else the password).
  func confirm() {
    let context = LAContext()
    context.localizedCancelTitle = word("cancel", "Cancel")
    let picked = scopes.filter { chosen.contains($0.id) }.map(\.id)
    context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: word("reason", "allow a program to read your still.fail data")) { ok, error in
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          if ok {
            self.done?(picked)
          } else if (error as? LAError)?.code != .userCancel {
            self.failed = error?.localizedDescription
          }
        }
      }
    }
  }
}

struct OutflowView: View {
  @ObservedObject var model: OutflowModel

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 12) {
        Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
          .resizable()
          .interpolation(.high)
          .frame(width: 48, height: 48)
        Text(model.confirming ? model.word("confirmTitle", "Confirm") : model.word("heading", "A program asks to read your still.fail data"))
          .font(.system(size: 18, weight: .bold, design: .rounded))
          .fixedSize(horizontal: false, vertical: true)
      }
      if model.confirming {
        Text(model.word("summary", ""))
          .font(.system(size: 13))
          .fixedSize(horizontal: false, vertical: true)
        if let failed = model.failed {
          Text(failed).font(.system(size: 11.5)).foregroundStyle(.red)
        }
        HStack {
          Button(model.word("back", "Back")) { model.confirming = false }
          Spacer()
          Button(model.word("refuse", "Don't Allow")) { model.done?(nil) }
          Button(model.word("confirm", "Confirm")) { model.confirm() }
            .keyboardShortcut(.defaultAction)
        }
      } else {
        identity
        Text(model.word("scopesHeading", "It asks for"))
          .font(.system(size: 13, weight: .semibold))
        ForEach(model.scopes) { scope in
          Toggle(isOn: Binding(get: { model.chosen.contains(scope.id) }, set: { on in
            if on { model.chosen.insert(scope.id) } else { model.chosen.remove(scope.id) }
          })) {
            VStack(alignment: .leading, spacing: 2) {
              Text(scope.name).font(.system(size: 13, weight: .medium))
              if !scope.why.isEmpty {
                Text(scope.why).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
              }
            }
          }
          .toggleStyle(.checkbox)
        }
        Text(model.word("until", "It keeps this until you revoke it in still.fail."))
          .font(.system(size: 11.5))
          .foregroundStyle(.secondary)
        HStack {
          Spacer()
          Button(model.word("refuse", "Don't Allow")) { model.done?(nil) }
            .keyboardShortcut(.cancelAction)
          Button(model.word("allow", "Allow")) { model.confirming = true }
            .disabled(model.chosen.isEmpty)
        }
      }
    }
    .padding(26)
    .frame(width: 500)
  }

  private var identity: some View {
    VStack(alignment: .leading, spacing: 6) {
      if model.signed {
        Label(model.word("signedBy", "Signed by") + " " + (model.text("signer") ?? model.text("teamId") ?? ""), systemImage: "checkmark.seal.fill")
          .foregroundStyle(.green)
      } else {
        Label(model.word("unsigned", "Not signed: macOS cannot say who made this program"), systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(.red)
      }
      row(model.word("program", "Program"), model.text("app") ?? model.text("identifier") ?? "")
      if let identifier = model.text("identifier") { row(model.word("identifier", "Identifier"), identifier) }
      row(model.word("path", "Path"), model.text("path") ?? "")
      if let said = model.word("said", "").nilIfEmpty { row(model.word("saidHeading", "It says (its own words)"), said) }
    }
    .font(.system(size: 12))
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.secondary.opacity(0.08)))
  }

  private func row(_ name: String, _ value: String) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Text(name).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
      Text(value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
    }
  }
}

private extension String {
  var nilIfEmpty: String? { isEmpty ? nil : self }
}
