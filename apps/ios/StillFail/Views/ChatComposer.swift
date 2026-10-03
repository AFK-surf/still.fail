import SwiftUI
import UIKit

/// A new conversation hands the same native text view to its chat. Draft text,
/// marked IME input and first-responder state survive the route handoff.
@MainActor final class ChatComposerSession {
    fileprivate var view: NativeChatComposer?
    fileprivate var editing = false
}

struct ChatComposer: UIViewRepresentable {
    @Environment(\.locale) private var locale
    @Binding var text: String
    let busy: Bool
    let enabled: Bool
    let attachmentEnabled: Bool
    let attachFiles: () -> Void
    let attachPhotos: () -> Void
    let send: () -> Void
    var session: ChatComposerSession? = nil
    @State private var measuredHeight: CGFloat = 52
    func makeUIView(context: Context) -> NativeComposerHost {
        let host = NativeComposerHost()
        let composer = session?.view ?? NativeChatComposer(frame: .zero)
        session?.view = composer; composer.session = session
        host.embed(composer)
        return host
    }
    func updateUIView(_ host: NativeComposerHost, context: Context) {
        guard let composer = host.composer else { return }
        composer.onTextChange = { text = $0 }
        composer.onHeightChange = { height in
            guard abs(measuredHeight - height) > 0.5 else { return }
            DispatchQueue.main.async { measuredHeight = height }
        }
        composer.onSend = send
        composer.configure(text: text, busy: busy, enabled: enabled, attachmentEnabled: attachmentEnabled,
                           attachFiles: attachFiles, attachPhotos: attachPhotos)
        _ = locale
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: NativeComposerHost, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        return CGSize(width: width, height: uiView.composer?.height(for: width) ?? measuredHeight)
    }
}

final class NativeComposerHost: UIView {
    fileprivate weak var composer: NativeChatComposer?
    func embed(_ view: NativeChatComposer) {
        composer = view; view.removeFromSuperview(); addSubview(view)
        accessibilityIdentifier = "composer.bar"
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        if composer?.frame != bounds { composer?.frame = bounds }
    }
}

final class NativeChatComposer: UIView, UITextViewDelegate {
    fileprivate weak var session: ChatComposerSession?
    var onTextChange: ((String) -> Void)?
    var onHeightChange: ((CGFloat) -> Void)?
    var onSend: (() -> Void)?
    private let plus = UIButton(type: .system)
    private let sendButton = UIButton(type: .system)
    private let editor = UITextView()
    private let placeholder = UILabel()
    // Share one native glass container so the two surfaces are composited
    // together. These are actual iOS 26 glass effects, rather than blur cards.
    private let glassContainer = UIVisualEffectView(effect: nil)
    private let inputMaterial = UIVisualEffectView(effect: nil)
    private let plusMaterial = UIVisualEffectView(effect: nil)
    private var lastHeight: CGFloat = 52
    private var measuredSize: (width: CGFloat, height: CGFloat)?
    private var language = ""
    private var attachFiles: (() -> Void)?
    private var attachPhotos: (() -> Void)?
    private var reduceTransparencyApplied: Bool?
    private var transparencyObserver: NSObjectProtocol?
    private var maximumHeight: CGFloat { max(148, min(260, (editor.font?.lineHeight ?? 22) * 3 + 28)) }
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        inputMaterial.layer.cornerRadius = 26; inputMaterial.clipsToBounds = true
        plusMaterial.layer.cornerRadius = 26; plusMaterial.clipsToBounds = true
        inputMaterial.accessibilityIdentifier = "composer.inputSurface"; plusMaterial.accessibilityIdentifier = "composer.plusSurface"
        glassContainer.backgroundColor = .clear
        glassContainer.contentView.backgroundColor = .clear
        addSubview(glassContainer)
        glassContainer.contentView.addSubview(inputMaterial); glassContainer.contentView.addSubview(plusMaterial)
        inputMaterial.contentView.addSubview(editor); inputMaterial.contentView.addSubview(placeholder); inputMaterial.contentView.addSubview(sendButton)
        plusMaterial.contentView.addSubview(plus)
        editor.delegate = self; editor.backgroundColor = .clear; editor.font = .preferredFont(forTextStyle: .body, compatibleWith: traitCollection)
        editor.adjustsFontForContentSizeCategory = true; applyTextInsets()
        editor.textContainer.lineFragmentPadding = 0; editor.isScrollEnabled = false
        editor.accessibilityIdentifier = "composer.text"
        placeholder.font = .preferredFont(forTextStyle: .body); placeholder.textColor = .placeholderText; placeholder.isUserInteractionEnabled = false
        plus.setImage(UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .medium)), for: .normal)
        plus.showsMenuAsPrimaryAction = true; plus.accessibilityIdentifier = "composer.attach"
        var config = UIButton.Configuration.filled()
        config.image = UIImage(systemName: "arrow.up", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
        config.cornerStyle = .capsule; config.contentInsets = .zero
        sendButton.configuration = config; sendButton.accessibilityIdentifier = "composer.send"
        sendButton.addAction(UIAction { [weak self] _ in self?.onSend?() }, for: .touchUpInside)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: NativeChatComposer, _: UITraitCollection) in
            view.editor.font = .preferredFont(forTextStyle: .body, compatibleWith: view.traitCollection); view.placeholder.font = view.editor.font
            view.applyTextInsets()
            view.measuredSize = nil; view.setNeedsLayout(); view.reportHeight()
        }
        transparencyObserver = NotificationCenter.default.addObserver(forName: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.refreshMaterials() }
        refreshMaterials()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    /// One line of text sits exactly in the middle of the 52 pt resting input.
    private var verticalInset: CGFloat { max(10, floor((52 - (editor.font?.lineHeight ?? 20)) / 2)) }
    private func applyTextInsets() {
        editor.textContainerInset = UIEdgeInsets(top: verticalInset, left: 11, bottom: verticalInset, right: 4)
    }
    func configure(text: String, busy: Bool, enabled: Bool, attachmentEnabled: Bool, attachFiles: @escaping () -> Void, attachPhotos: @escaping () -> Void) {
        // Do not overwrite marked Chinese/Japanese IME composition on a topic tick.
        if editor.text != text && editor.markedTextRange == nil {
            let old = editor.text ?? "", selection = editor.selectedRange
            let inserted = !old.isEmpty && text.hasSuffix(old) ? text.utf16.count - old.utf16.count : 0
            editor.text = text
            measuredSize = nil
            let location = old.isEmpty ? text.utf16.count : min(text.utf16.count, selection.location + max(0, inserted))
            editor.selectedRange = NSRange(location: location, length: min(selection.length, text.utf16.count - location))
            reportHeight()
        }
        self.attachFiles = attachFiles; self.attachPhotos = attachPhotos
        if language != L10n.locale.identifier {
            language = L10n.locale.identifier
            placeholder.text = L10n.text("发送消息"); editor.accessibilityLabel = L10n.text("发送消息")
            plus.accessibilityLabel = L10n.text("添加附件"); sendButton.accessibilityLabel = L10n.text("发送消息")
            plus.menu = UIMenu(children: [
                UIAction(title: L10n.text("选择照片"), image: UIImage(systemName: "photo")) { [weak self] _ in self?.attachPhotos?() },
                UIAction(title: L10n.text("选择文件"), image: UIImage(systemName: "doc")) { [weak self] _ in self?.attachFiles?() }
            ])
        }
        placeholder.isHidden = !editor.text.isEmpty
        if plus.isEnabled != (attachmentEnabled && !busy) { plus.isEnabled = attachmentEnabled && !busy }
        if sendButton.isEnabled != (enabled && !busy) { sendButton.isEnabled = enabled && !busy }
        refreshMaterials()
    }
    private func refreshMaterials() {
        let reduced = UIAccessibility.isReduceTransparencyEnabled
        guard reduceTransparencyApplied != reduced else { return }; reduceTransparencyApplied = reduced
        if reduced {
            glassContainer.effect = nil
        } else {
            let container = UIGlassContainerEffect()
            container.spacing = 8
            glassContainer.effect = container
        }
        for material in [inputMaterial, plusMaterial] {
            if reduced {
                material.effect = nil
            } else {
                let glass = UIGlassEffect(style: .regular)
                glass.isInteractive = true
                material.effect = glass
            }
            material.backgroundColor = reduced ? .secondarySystemBackground : .clear
            material.layer.borderWidth = reduced ? 1 / max(1, traitCollection.displayScale) : 0
            material.layer.borderColor = UIColor.separator.cgColor
        }
    }
    func height(for width: CGFloat) -> CGFloat {
        if let measuredSize, abs(measuredSize.width - width) < 0.5 { return measuredSize.height }
        let editorWidth = max(1, width - 62 - 52)
        let natural = editor.sizeThatFits(CGSize(width: editorWidth, height: .greatestFiniteMagnitude)).height
        let height = max(52, min(maximumHeight, ceil(natural)))
        measuredSize = (width, height)
        return height
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        let h = max(52, bounds.height), inputX: CGFloat = 62, inputWidth = max(1, bounds.width - inputX)
        glassContainer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: h)
        // At rest both surfaces are the same 52 pt; a growing draft only grows the
        // input, while the attachment button stays a circle on the same baseline.
        plusMaterial.frame = CGRect(x: 0, y: h - 52, width: 52, height: 52); plus.frame = plusMaterial.bounds
        inputMaterial.frame = CGRect(x: inputX, y: 0, width: inputWidth, height: h)
        editor.frame = CGRect(x: 5, y: 0, width: max(1, inputWidth - 52), height: h)
        placeholder.frame = CGRect(x: 16, y: verticalInset, width: max(1, inputWidth - 66), height: ceil(editor.font?.lineHeight ?? 22))
        sendButton.frame = CGRect(x: inputWidth - 46, y: h - 46, width: 40, height: 40)
        editor.isScrollEnabled = height(for: bounds.width) >= maximumHeight
        reportHeight()
    }
    private func reportHeight() {
        let h = height(for: bounds.width > 0 ? bounds.width : 320)
        if abs(h - lastHeight) > 0.5 { lastHeight = h; invalidateIntrinsicContentSize(); onHeightChange?(h) }
    }
    deinit { if let transparencyObserver { NotificationCenter.default.removeObserver(transparencyObserver) } }
    func textViewDidChange(_ textView: UITextView) {
        measuredSize = nil
        placeholder.isHidden = !textView.text.isEmpty
        onTextChange?(textView.text); reportHeight()
    }
    func textViewDidBeginEditing(_ textView: UITextView) { session?.editing = true }
    func textViewDidEndEditing(_ textView: UITextView) { if window != nil { session?.editing = false } }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, session?.editing == true, !editor.isFirstResponder {
            DispatchQueue.main.async { [weak self] in if self?.window != nil { self?.editor.becomeFirstResponder() } }
        }
    }
}
