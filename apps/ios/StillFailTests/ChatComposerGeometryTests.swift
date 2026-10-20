import XCTest
import UIKit
@testable import StillFail

final class ChatComposerGeometryTests: XCTestCase {
    @MainActor private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }

    @MainActor func testComposerUsesNativeGlassInOneSharedContainer() throws {
        guard !UIAccessibility.isReduceTransparencyEnabled else { throw XCTSkip("Reduce Transparency intentionally replaces glass.") }
        let composer = NativeChatComposer(frame: CGRect(x: 0, y: 0, width: 320, height: 52))
        composer.configure(text: "Glass over messages", busy: false, enabled: true, attachmentEnabled: true, attachFiles: {}, attachPhotos: {})
        composer.layoutIfNeeded()
        let effects = descendants(composer).compactMap { $0 as? UIVisualEffectView }
        let input = try XCTUnwrap(effects.first { $0.accessibilityIdentifier == "composer.inputSurface" })
        let plus = try XCTUnwrap(effects.first { $0.accessibilityIdentifier == "composer.plusSurface" })
        XCTAssertTrue(input.effect is UIGlassEffect)
        XCTAssertTrue(plus.effect is UIGlassEffect)
        XCTAssertEqual(effects.filter { $0.effect is UIGlassContainerEffect }.count, 1)
        XCTAssertTrue(input.superview === plus.superview)
        XCTAssertEqual(input.backgroundColor, UIColor.clear)
        XCTAssertEqual(plus.backgroundColor, UIColor.clear)
        XCTAssertTrue(try XCTUnwrap(input.effect as? UIGlassEffect).isInteractive)
    }

    @MainActor func testChatHeaderUsesSystemScrollEdgeEffect() {
        let controller = ChatTimelineController()
        controller.loadViewIfNeeded()
        let scrollView = controller.contentScrollView(for: .top)
        XCTAssertNotNil(scrollView)
        XCTAssertTrue(scrollView?.topEdgeEffect.style === UIScrollEdgeEffect.Style.soft)
        XCTAssertEqual(scrollView?.topEdgeEffect.isHidden, false)
        // The composer retains its own glass surfaces without a full-width bottom effect.
        XCTAssertEqual(scrollView?.bottomEdgeEffect.isHidden, true)
    }

    @MainActor func testAttachmentAndInputSurfacesShareHeightAcrossWidthsAndDraftSizes() throws {
        let composer = NativeChatComposer(frame: .zero)
        for width in [320.0, 744.0] {
            for text in ["Hello", String(repeating: "A longer multiline draft.\n", count: 30)] {
                composer.frame = CGRect(x: 0, y: 0, width: width, height: 52)
                composer.configure(text: text, busy: false, enabled: true, attachmentEnabled: true, attachFiles: {}, attachPhotos: {})
                let height = composer.height(for: width)
                composer.frame.size.height = height
                composer.setNeedsLayout(); composer.layoutIfNeeded()
                let input = try XCTUnwrap(descendants(composer).first { $0.accessibilityIdentifier == "composer.inputSurface" })
                let plus = try XCTUnwrap(descendants(composer).first { $0.accessibilityIdentifier == "composer.plusSurface" })
                // Equal at rest; the attachment button stays a circle on the input's baseline.
                if text == "Hello" { XCTAssertEqual(input.frame.height, plus.frame.height, accuracy: 0.5) }
                XCTAssertEqual(plus.frame.width, plus.frame.height, accuracy: 0.5)
                XCTAssertEqual(plus.frame.maxY, input.frame.maxY, accuracy: 0.5)
                XCTAssertEqual(input.frame.height, height, accuracy: 0.5)
                XCTAssertGreaterThanOrEqual(height, 52)
            }
        }
    }

    @MainActor func testLargeTextKeepsSurfacesAlignedAndTextEditableDuringSend() throws {
        let composer = NativeChatComposer(frame: CGRect(x: 0, y: 0, width: 320, height: 52))
        composer.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        composer.configure(text: String(repeating: "Draft ", count: 30), busy: true, enabled: false, attachmentEnabled: false, attachFiles: {}, attachPhotos: {})
        composer.frame.size.height = composer.height(for: 320)
        composer.setNeedsLayout(); composer.layoutIfNeeded()
        let editor = try XCTUnwrap(descendants(composer).compactMap { $0 as? UITextView }.first)
        let input = try XCTUnwrap(descendants(composer).first { $0.accessibilityIdentifier == "composer.inputSurface" })
        let plus = try XCTUnwrap(descendants(composer).first { $0.accessibilityIdentifier == "composer.plusSurface" })
        XCTAssertEqual(plus.frame.maxY, input.frame.maxY, accuracy: 0.5)
        XCTAssertTrue(editor.isEditable)
        XCTAssertTrue(editor.isUserInteractionEnabled)
    }

    @MainActor func testComposerReparentingKeepsNativeTextViewAndSelection() throws {
        let composer = NativeChatComposer(frame: CGRect(x: 0, y: 0, width: 320, height: 52))
        composer.configure(text: "Hello composer", busy: false, enabled: true, attachmentEnabled: true, attachFiles: {}, attachPhotos: {})
        let first = NativeComposerHost(), second = NativeComposerHost()
        first.embed(composer)
        let editor = try XCTUnwrap(descendants(first).compactMap { $0 as? UITextView }.first)
        editor.selectedRange = NSRange(location: 6, length: 8)
        second.embed(composer)
        XCTAssertTrue(first.subviews.isEmpty)
        XCTAssertTrue(descendants(second).contains { $0 === editor })
        XCTAssertEqual(editor.text, "Hello composer")
        XCTAssertEqual(editor.selectedRange, NSRange(location: 6, length: 8))
    }
}
