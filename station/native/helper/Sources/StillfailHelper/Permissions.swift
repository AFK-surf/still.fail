// The window that asks for this app's grants, as Cue's Computer Use has it (PermissionAuthWindow.swift there): a row
// per grant with its state as macOS has it now, Allow opens its System Settings pane with PermissionFlow's floating
// panel beside it holding this app to drag into the list; rows turn granted as macOS records the drop (looked at
// every 0.8 s), and the window closes itself once all are. A grant taken while it was up starts this app again, the
// grant then in effect (Daemon.restart). The words are the station's (`permissions.show` {words}), in its language.
//
// It shows the grants asked for (`grants`): the screen's two, or the drive's folders (Files.swift). A folder is granted
// by macOS's own prompt, not in System Settings' lists: its Allow has this app open the folder and macOS asks (or, refused
// before, opens Files and Folders, where the app has a switch for it). Asked for more while it is up, it shows them too.
import AppKit
import Combine
import PermissionFlow
import SwiftUI

enum Grant: String, CaseIterable, Identifiable {
  case screenRecording = "capture"
  case accessibility = "control"
  case documents, desktop, downloads, removable, network
  var id: String { rawValue }
  /// The System Settings pane it is dragged into; none for a folder (macOS asks).
  var pane: PermissionFlowPane? {
    switch self {
    case .screenRecording: .screenRecording
    case .accessibility: .accessibility
    default: nil
    }
  }
  var folder: FileGrant? { FileGrant(rawValue: rawValue) }
  var symbol: String {
    switch self {
    case .screenRecording: "rectangle.dashed.badge.record"
    case .accessibility: "figure.arms.open"
    case .documents: "doc"
    case .desktop: "menubar.dock.rectangle"
    case .downloads: "arrow.down.circle"
    case .removable: "externaldrive"
    case .network: "network"
    }
  }
}

@MainActor
final class Permissions {
  static let shared = Permissions()
  private var windowController: NSWindowController?
  private let model = PermissionsModel()
  private var flow: PermissionFlowController?
  private weak var daemon: Daemon?
  private let delegate = WindowDelegate()
  private var previous: NSRunningApplication?

  var isShown: Bool { windowController != nil }
  /// The grants it shows.
  var asked: [String] { model.asked.map(\.rawValue) }

  func show(words: [String: Any], grants: [String], paths: [String: String] = [:], daemon: Daemon) {
    self.daemon = daemon
    let asked = grants.compactMap(Grant.init(rawValue:))
    // Up already: what it shows, and what is asked now.
    model.asked = windowController == nil ? asked : model.asked + asked.filter { !model.asked.contains($0) }
    model.paths.merge(paths) { _, new in new }
    model.words.merge(words.compactMapValues { $0 as? String }) { _, new in new }
    if let panel = words["panel"] as? [String: String] { PermissionFlowLocalizer.words = panel }
    let flow = self.flow ?? PermissionFlow.makeController(configuration: .init(promptForAccessibilityTrust: false))
    self.flow = flow
    model.onRowsChanged = { [weak daemon] rows in
      flow.guidanceSteps = rows.compactMap { row in row.grant.pane.map { (pane: $0, granted: row.granted) } }
      // The station hears of it (the drive's folders readable now).
      daemon?.notify(["event": "grants"])
    }
    model.onAuthorize = { [weak model] grant in
      if let folder = grant.folder {
        Files.ask(folder, path: model?.paths[grant.rawValue])
        return
      }
      guard let pane = grant.pane else { return }
      flow.resetDroppedApps()
      // This app is what macOS grants: what is dragged in.
      flow.authorize(pane: pane, suggestedAppURLs: [Bundle.main.bundleURL])
    }
    model.onAllGranted = { [weak self] in self?.windowController?.window?.performClose(nil) }

    if let window = windowController?.window {
      model.startPolling()
      NSApp.activate(ignoringOtherApps: true)
      window.makeKeyAndOrderFront(nil)
      return
    }
    previous = NSWorkspace.shared.frontmostApplication
    let host = NSHostingController(rootView: PermissionsView(model: model, onClose: { [weak self] in self?.windowController?.window?.performClose(nil) }))
    let window = NSWindow(contentViewController: host)
    window.title = model.word("title", "still.fail")
    window.styleMask = [.titled, .closable, .fullSizeContentView]
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isMovableByWindowBackground = true
    window.isReleasedWhenClosed = false
    window.level = .floating
    window.center()
    delegate.closed = { [weak self] in self?.closed() }
    window.delegate = delegate
    let controller = NSWindowController(window: window)
    windowController = controller
    // An accessory app shows a window in front only as a regular one; it is one again once the window closes.
    _ = NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    controller.showWindow(nil)
    model.startPolling()
  }

  private func closed() {
    model.stopPolling()
    windowController = nil
    flow?.closePanel(returnToPreviousApp: false)
    previous?.activate(options: [.activateIgnoringOtherApps])
    previous = nil
    DispatchQueue.main.async { _ = NSApp.setActivationPolicy(.accessory) }
    // A grant taken while it was up is had once this app starts again.
    let daemon = daemon
    DispatchQueue.global().async {
      if daemon?.grantedSince() == true { DispatchQueue.main.async { daemon?.restart() } }
    }
  }
}

private final class WindowDelegate: NSObject, NSWindowDelegate {
  var closed: (() -> Void)?
  func windowWillClose(_: Notification) {
    closed?()
  }
}

@MainActor
final class PermissionsModel: ObservableObject {
  struct Row: Identifiable, Equatable {
    let grant: Grant
    let granted: Bool
    var id: String { grant.rawValue }
  }

  @Published var rows: [Row] = []
  @Published var words: [String: String] = [:]
  /// The grants it shows, in order.
  var asked: [Grant] = [] {
    didSet { rows = asked.map { grant in Row(grant: grant, granted: rows.first { $0.grant == grant }?.granted ?? false) } }
  }
  /// A disk's folder for its grant (removable, network): the one macOS asks about.
  var paths: [String: String] = [:]
  /// A folder's grant refused before: its Allow opens System Settings.
  @Published var denied: Set<Grant> = []
  var onAuthorize: ((Grant) -> Void)?
  var onRowsChanged: (([Row]) -> Void)?
  var onAllGranted: (() -> Void)?
  private var active: Grant?
  private var timer: Timer?
  private var looking = false
  private var closing: Task<Void, Never>?

  func word(_ key: String, _ otherwise: String) -> String {
    words[key] ?? otherwise
  }

  var allGranted: Bool { !rows.isEmpty && rows.allSatisfy(\.granted) }

  func authorize(_ grant: Grant) {
    active = grant
    onAuthorize?(grant)
  }

  func startPolling() {
    refresh()
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.refresh() }
    }
  }

  func stopPolling() {
    active = nil
    timer?.invalidate()
    timer = nil
    closing?.cancel()
    closing = nil
  }

  /// The grants as a new process has them (this one keeps what it started with), off the main thread.
  func refresh() {
    if looking { return }
    looking = true
    DispatchQueue.global().async {
      let fresh = Status.fresh() ?? [:]
      let files = fresh["files"] as? [String: String] ?? [:]
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        looking = false
        let granted = { (grant: Grant) -> Bool in
          grant.folder == nil ? (fresh[grant.rawValue] as? Bool) ?? false : files["all"] == "granted" || files[grant.rawValue] == "granted"
        }
        let next = asked.map { Row(grant: $0, granted: granted($0)) }
        denied = Set(asked.filter { $0.folder != nil && files[$0.rawValue] == "denied" })
        if next != rows {
          rows = next
          onRowsChanged?(next)
        }
        // The one being granted is: on to the next missing one dragged in (a folder's prompt is a person's own click).
        if let active, next.contains(where: { $0.grant == active && $0.granted }) {
          self.active = nil
          if let missing = next.first(where: { !$0.granted && $0.grant.pane != nil }) { authorize(missing.grant) }
        }
        closeWhenAllGranted()
      }
    }
  }

  private func closeWhenAllGranted() {
    guard allGranted else {
      closing?.cancel()
      closing = nil
      return
    }
    guard closing == nil else { return }
    closing = Task { @MainActor [weak self] in
      // The granted rows shown for a beat, then the window closes by itself.
      try? await Task.sleep(nanoseconds: 1_200_000_000)
      guard let self, !Task.isCancelled, allGranted else { return }
      onAllGranted?()
    }
  }
}

struct PermissionsView: View {
  @ObservedObject var model: PermissionsModel
  let onClose: () -> Void

  var body: some View {
    VStack(spacing: 18) {
      Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
        .resizable()
        .interpolation(.high)
        .frame(width: 72, height: 72)
        .padding(.top, 10)
      VStack(spacing: 8) {
        Text(model.word("title", "Let still.fail see and control this Mac"))
          .font(.system(size: 20, weight: .bold, design: .rounded))
        Text(model.word("subtitle", "Someone asked to see this Mac's screen from the still.fail app."))
          .font(.system(size: 13))
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: 440)
      }
      VStack(spacing: 10) {
        ForEach(model.rows) { row in
          PermissionRow(row: row, model: model) { model.authorize(row.grant) }
        }
      }
      if model.allGranted {
        Label(model.word("done", "Permissions enabled"), systemImage: "checkmark.circle.fill")
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(.green)
      }
    }
    .onExitCommand(perform: onClose)
    .padding(.top, 26)
    .padding(.horizontal, 26)
    .padding(.bottom, 26)
    .frame(width: 500)
  }
}

private struct PermissionRow: View {
  let row: PermissionsModel.Row
  @ObservedObject var model: PermissionsModel
  let onAllow: () -> Void
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: row.grant.symbol)
        .font(.system(size: 22))
        .frame(width: 36, height: 36)
        .opacity(row.granted ? 0.7 : 1)
      VStack(alignment: .leading, spacing: 2) {
        Text(model.word(row.grant.rawValue, row.grant.rawValue.capitalized))
          .font(.system(size: 14, weight: .semibold))
        Text(model.denied.contains(row.grant) ? model.word("deniedWhy", "Refused before: Allow opens System Settings › Files and Folders, to switch it on there") : model.word("\(row.grant.rawValue)Why", ""))
          .font(.system(size: 11.5))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer()
      if row.granted {
        Image(systemName: "checkmark").foregroundStyle(.green).font(.system(size: 14, weight: .semibold))
      } else {
        Button(model.word("allow", "Allow"), action: onAllow)
          .buttonStyle(.borderless)
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(.white)
          .padding(.horizontal, 16)
          .padding(.vertical, 7)
          .background(Capsule(style: .continuous).fill(Color.accentColor))
      }
    }
    .padding(.vertical, 12)
    .padding(.horizontal, 14)
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(colorScheme == .dark ? Color.white.opacity(0.085) : Color.white.opacity(0.94))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.08), lineWidth: 1)
    )
  }
}
