import SwiftUI
import UIKit

/// A single masked material fades into the scrolling content. Four stacked
/// materials made the old header nearly opaque and added four backdrop passes.
struct ProgressiveHeaderBlur: UIViewRepresentable {
    func makeUIView(context: Context) -> NavigationBlurAnchor { NavigationBlurAnchor() }
    func updateUIView(_ view: NavigationBlurAnchor, context: Context) { view.attach() }
    static func dismantleUIView(_ view: NavigationBlurAnchor, coordinator: ()) { view.detach() }
}

/// A view anchor never introduces a navigation item or a child controller, so
/// SwiftUI retains ownership of the title, back button and toolbar button group.
final class NavigationBlurAnchor: UIView {
    private let blur = ProgressiveBlurView(frame: .zero)
    private weak var installedBar: UINavigationBar?
    override init(frame: CGRect) { super.init(frame: frame); isUserInteractionEnabled = false; backgroundColor = .clear }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { detach() } else { DispatchQueue.main.async { [weak self] in self?.attach() } }
    }
    override func layoutSubviews() { super.layoutSubviews(); attach() }
    override func safeAreaInsetsDidChange() { super.safeAreaInsetsDidChange(); attach() }
    func attach() {
        guard window != nil else { return }
        var responder: UIResponder? = self
        var navigation: UINavigationController?
        while let current = responder {
            if let controller = current as? UIViewController, let found = controller.navigationController { navigation = found; break }
            responder = current.next
        }
        guard let navigation else { return }
        let bar = navigation.navigationBar
        if installedBar !== bar {
            detach()
            NavigationChromeLease.acquire(bar)
            bar.insertSubview(blur, at: 0); installedBar = bar
        }
        // Converting the bar's actual position also covers iPad split columns;
        // a status-bar height guess left a white strip above the old material.
        let top = max(0, bar.convert(bar.bounds, to: window).minY)
        blur.frame = CGRect(x: 0, y: -top, width: bar.bounds.width, height: bar.bounds.height + top + 36)
        // UIKit's navigation-item content can live outside the bar's simple
        // subview ordering on iOS 26. Negative layer depth keeps the backdrop
        // below that content as well as below the bar's own subviews.
        blur.layer.zPosition = -1
        bar.sendSubviewToBack(blur)
        blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]; blur.refresh()
    }
    func detach() {
        blur.removeFromSuperview()
        if let installedBar { NavigationChromeLease.release(installedBar) }
        installedBar = nil
    }
}

final class ProgressiveBlurView: UIView {
    private let material = UIVisualEffectView(effect: nil)
    private let fade = CAGradientLayer()
    private var transparencyObserver: NSObjectProtocol?
    private var reduced: Bool?
    override init(frame: CGRect) {
        super.init(frame: frame); isUserInteractionEnabled = false
        backgroundColor = .clear
        material.isUserInteractionEnabled = false
        // An eased ramp rather than a straight edge: fully frosted behind the title,
        // then thinning out over the content below the bar.
        fade.colors = [1, 1, 0.82, 0.45, 0.16, 0].map { UIColor.black.withAlphaComponent($0).cgColor }
        fade.locations = [0, 0.5, 0.66, 0.8, 0.91, 1]
        material.layer.mask = fade
        addSubview(material)
        transparencyObserver = NotificationCenter.default.addObserver(forName: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        refresh()
    }
    deinit { if let transparencyObserver { NotificationCenter.default.removeObserver(transparencyObserver) } }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func refresh() {
        let enabled = UIAccessibility.isReduceTransparencyEnabled
        guard reduced != enabled else { return }; reduced = enabled
        material.effect = enabled ? nil : UIBlurEffect(style: .systemThinMaterial)
        material.backgroundColor = enabled ? .systemBackground : .clear
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        material.frame = bounds
        CATransaction.begin(); CATransaction.setDisableActions(true)
        fade.frame = bounds
        CATransaction.commit()
    }
}

/// Clear UIKit's rectangular background and hairline while a chat is visible.
/// Ref-counting handles the overlapping anchors during new-chat handoff, and
/// restores the original appearances on leaving the final chat page.
@MainActor private enum NavigationChromeLease {
    private final class Lease {
        weak var bar: UINavigationBar?
        var count = 1
        let standard: UINavigationBarAppearance
        let scroll: UINavigationBarAppearance?
        let compact: UINavigationBarAppearance?
        let compactScroll: UINavigationBarAppearance?
        init(_ bar: UINavigationBar) {
            self.bar = bar; standard = bar.standardAppearance
            scroll = bar.scrollEdgeAppearance; compact = bar.compactAppearance; compactScroll = bar.compactScrollEdgeAppearance
        }
    }
    private static var leases: [ObjectIdentifier: Lease] = [:]
    static func acquire(_ bar: UINavigationBar) {
        leases = leases.filter { $0.value.bar != nil }
        let key = ObjectIdentifier(bar)
        if let lease = leases[key] { lease.count += 1; return }
        leases[key] = Lease(bar)
        let appearance = bar.standardAppearance.copy() as! UINavigationBarAppearance
        appearance.configureWithTransparentBackground()
        appearance.shadowColor = .clear
        bar.standardAppearance = appearance; bar.scrollEdgeAppearance = appearance
        bar.compactAppearance = appearance; bar.compactScrollEdgeAppearance = appearance
    }
    static func release(_ bar: UINavigationBar) {
        let key = ObjectIdentifier(bar)
        guard let lease = leases[key] else { return }
        lease.count -= 1
        guard lease.count == 0 else { return }
        bar.standardAppearance = lease.standard; bar.scrollEdgeAppearance = lease.scroll
        bar.compactAppearance = lease.compact; bar.compactScrollEdgeAppearance = lease.compactScroll
        leases.removeValue(forKey: key)
    }
}
