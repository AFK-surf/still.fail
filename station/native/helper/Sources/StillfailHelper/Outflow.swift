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
    // As still.fail's dialogs: no title bar, its own rounded white panel with a soft shadow (OutflowView draws it).
    host.view.wantsLayer = true
    host.view.layer?.backgroundColor = .clear
    let window = OutflowPanel(contentRect: NSRect(origin: .zero, size: host.view.fittingSize), styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentViewController = host
    window.title = model.word("title", "still.fail")
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
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

/// A borderless window that still takes the keyboard (its buttons, Esc, Return).
private final class OutflowPanel: NSWindow {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
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

/// still.fail's colours and sizes (web/src/styles/global.css.ts), light and dark.
struct Still {
  let dark: Bool
  var canvas: Color { dark ? Color(hex: 0x1F2023) : .white }
  var text: Color { dark ? Color(hex: 0xECEDED) : Color(hex: 0x2B2F36) }
  var muted: Color { dark ? Color(hex: 0xA8AAAE) : Color(hex: 0x565B62) }
  var lineStrong: Color { dark ? Color.white.opacity(0.18) : Color(hex: 0xC6C8CD) }
  var neutral: Color { dark ? Color.white.opacity(0.06) : Color(red: 36 / 255, green: 39 / 255, blue: 43 / 255).opacity(0.075) }
  var primary: Color { dark ? Color(hex: 0xECEDED) : Color(hex: 0x24272B) }
  var onPrimary: Color { dark ? Color(hex: 0x1F2023) : .white }
  var green: Color { dark ? Color(hex: 0x6FCF97) : Color(hex: 0x026039) }
  var red: Color { dark ? Color(hex: 0xF08A8F) : Color(hex: 0x9A2830) }
  /// The brand's dot.
  static let dot = Color(hex: 0xE5704A)
  static let pad: CGFloat = 24
  /// The panel's corner: its padding plus a button's half height (still.fail's dialogs, concentric).
  static let corner: CGFloat = 42
  static let inner: CGFloat = 18
}

extension Color {
  init(hex: UInt32) {
    self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
  }
}

/// still.fail's pill buttons: 36 high, 16 in; the primary in ink with white words, the other on the canvas with a line.
/// Drawn as a view of its own and tapped (a Button's platform cell clips the pill's round ends); Return and Esc reach
/// them through `keys`.
struct Pill: View {
  let still: Still
  let label: String
  var primary = false
  var disabled = false
  let action: () -> Void
  var body: some View {
    Text(label)
      .font(.system(size: 13, weight: .medium))
      .foregroundStyle(primary ? still.onPrimary : still.text)
      .padding(.horizontal, 16)
      .frame(height: 36)
      .background(RoundedRectangle(cornerRadius: 18, style: .circular).fill(primary ? still.primary : still.canvas))
      .overlay(RoundedRectangle(cornerRadius: 18, style: .circular).strokeBorder(primary ? still.primary : still.lineStrong, lineWidth: 1))
      .contentShape(RoundedRectangle(cornerRadius: 18, style: .circular))
      .opacity(disabled ? 0.4 : 1)
      .onTapGesture { if !disabled { action() } }
      .accessibilityAddTraits(.isButton)
      .accessibilityAction { if !disabled { action() } }
  }
}

/// Return and Esc for a step: buttons with no size of their own.
struct Keys: View {
  let enter: () -> Void
  let escape: () -> Void
  var body: some View {
    ZStack {
      Button("", action: enter).keyboardShortcut(.defaultAction)
      Button("", action: escape).keyboardShortcut(.cancelAction)
    }
    .frame(width: 0, height: 0)
    .opacity(0)
    .accessibilityHidden(true)
  }
}

/// still.fail's checkbox: 18, its corner 6; ticked, the ink with a white check.
struct StillCheck: ToggleStyle {
  let still: Still
  func makeBody(configuration: Configuration) -> some View {
    HStack(alignment: .top, spacing: 10) {
      ZStack {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(configuration.isOn ? still.primary : still.canvas)
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .strokeBorder(configuration.isOn ? still.primary : still.lineStrong, lineWidth: 1)
        if configuration.isOn {
          Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(still.onPrimary)
        }
      }
      .frame(width: 18, height: 18)
      .padding(.top, 1)
      configuration.label
      Spacer(minLength: 0)
    }
    .contentShape(Rectangle())
    .onTapGesture { configuration.isOn.toggle() }
    .accessibilityAddTraits(.isButton)
  }
}

/// still.fail's mark: an s and the orange dot.
struct StillMark: View {
  let still: Still
  var body: some View {
    HStack(alignment: .lastTextBaseline, spacing: 1) {
      Text("s").font(.system(size: 22, weight: .bold)).foregroundStyle(still.text)
      Circle().fill(Still.dot).frame(width: 5.5, height: 5.5)
    }
  }
}

struct OutflowView: View {
  @ObservedObject var model: OutflowModel
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    let still = Still(dark: scheme == .dark)
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 10) {
        StillMark(still: still)
        Text(model.confirming ? model.word("confirmTitle", "Confirm") : model.word("heading", "A program asks to read your still.fail data"))
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(still.text)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.bottom, 18)
      if model.confirming {
        Text(model.word("summary", ""))
          .font(.system(size: 14))
          .lineSpacing(4)
          .foregroundStyle(still.text)
          .fixedSize(horizontal: false, vertical: true)
        if let failed = model.failed {
          Text(failed).font(.system(size: 12)).foregroundStyle(still.red).padding(.top, 8)
        }
        HStack(spacing: 8) {
          Pill(still: still, label: model.word("back", "Back")) { model.confirming = false }
          Spacer()
          Pill(still: still, label: model.word("refuse", "Don't Allow")) { model.done?(nil) }
          Pill(still: still, label: model.word("confirm", "Confirm"), primary: true) { model.confirm() }
        }
        .padding(.top, Still.pad)
        .background(Keys(enter: { model.confirm() }, escape: { model.confirming = false }))
      } else {
        identity(still)
        Text(model.word("scopesHeading", "It asks for"))
          .font(.system(size: 12))
          .foregroundStyle(still.muted)
          .padding(.top, 18)
          .padding(.bottom, 10)
        VStack(alignment: .leading, spacing: 12) {
          ForEach(model.scopes) { scope in
            Toggle(isOn: Binding(get: { model.chosen.contains(scope.id) }, set: { on in
              if on { model.chosen.insert(scope.id) } else { model.chosen.remove(scope.id) }
            })) {
              VStack(alignment: .leading, spacing: 2) {
                Text(scope.name).font(.system(size: 13, weight: .medium)).foregroundStyle(still.text)
                if !scope.why.isEmpty {
                  Text(scope.why).font(.system(size: 12)).foregroundStyle(still.muted).fixedSize(horizontal: false, vertical: true)
                }
              }
            }
            .toggleStyle(StillCheck(still: still))
          }
        }
        Text(model.word("until", "It keeps this until you revoke it in still.fail."))
          .font(.system(size: 12))
          .foregroundStyle(still.muted)
          .padding(.top, 16)
        HStack(spacing: 8) {
          Spacer()
          Pill(still: still, label: model.word("refuse", "Don't Allow")) { model.done?(nil) }
          Pill(still: still, label: model.word("allow", "Allow"), primary: true, disabled: model.chosen.isEmpty) { model.confirming = true }
        }
        .padding(.top, Still.pad)
        .background(Keys(enter: { if !model.chosen.isEmpty { model.confirming = true } }, escape: { model.done?(nil) }))
      }
    }
    .padding(Still.pad)
    .frame(width: 460)
    // The shadow on the panel alone (on the whole view it falls under every word and button too).
    .background(
      RoundedRectangle(cornerRadius: Still.corner, style: .continuous)
        .fill(still.canvas)
        .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.1), radius: 32, y: 24)
    )
    .overlay(RoundedRectangle(cornerRadius: Still.corner, style: .continuous).strokeBorder(still.lineStrong.opacity(0.6), lineWidth: 0.5))
    .padding(40)
  }

  private func identity(_ still: Still) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      if model.signed {
        pill(model.word("signedBy", "Signed by") + " " + (model.text("signer") ?? model.text("teamId") ?? ""), "checkmark.seal.fill", still.green)
      } else {
        pill(model.word("unsigned", "Not signed: macOS cannot say who made this program"), "exclamationmark.triangle.fill", still.red)
      }
      row(still, model.word("program", "Program"), model.text("app") ?? model.text("identifier") ?? "")
      if let identifier = model.text("identifier") { row(still, model.word("identifier", "Identifier"), identifier) }
      row(still, model.word("path", "Path"), model.text("path") ?? "")
      if let said = model.word("said", "").nilIfEmpty { row(still, model.word("saidHeading", "It says (its own words)"), said) }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: Still.inner, style: .continuous).fill(still.neutral))
  }

  private func pill(_ words: String, _ icon: String, _ ink: Color) -> some View {
    Label(words, systemImage: icon)
      .font(.system(size: 12, weight: .medium))
      .foregroundStyle(ink)
      .padding(.horizontal, 10)
      .padding(.vertical, 4)
      .background(Capsule().fill(ink.opacity(0.14)))
      .fixedSize(horizontal: false, vertical: true)
  }

  private func row(_ still: Still, _ name: String, _ value: String) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Text(name).font(.system(size: 12)).foregroundStyle(still.muted).frame(width: 72, alignment: .leading)
      Text(value).font(.system(size: 13)).foregroundStyle(still.text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
    }
  }
}

private extension String {
  var nilIfEmpty: String? { isEmpty ? nil : self }
}
