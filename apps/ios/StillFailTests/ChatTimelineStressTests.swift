import XCTest
import UIKit
@testable import StillFail

final class ChatTimelineStressTests: XCTestCase {
    @MainActor func testOpeningRestoresSavedPositionAfterLoadingAndPersistsNativeOffset() async throws {
        let controller = ChatTimelineController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        var positioned = 0
        var readerAtEnd = true
        var remembered: (Int?, Double?)?
        controller.positionReady = { positioned += 1 }
        controller.endChanged = { readerAtEnd = $0 }
        controller.rememberPlace = { remembered = ($0, $1) }
        controller.update([ChatTimelineRow(id: "empty", kind: .empty)], language: "en", loaded: false)
        controller.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(positioned, 0, "A loading placeholder must not declare that the reader reached the end")
        let rows = (0..<500).map { index in
            ChatTimelineRow(id: "row:\(index)", kind: .message, value: .object([
                "seq": .number(Double(index)), "authorKind": .string("person"), "author": .string("me"),
                "mine": .bool(true), "text": .string("Message \(index)")]))
        }
        controller.update(rows, language: "en", initialSeq: 250, initialOffset: -18, loaded: true)
        try await Task.sleep(nanoseconds: 150_000_000)
        let collection = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? UICollectionView }.first)
        collection.layoutIfNeeded()
        let frame = try XCTUnwrap(collection.layoutAttributesForItem(at: IndexPath(item: 250, section: 0))).frame
        XCTAssertEqual(frame.minY - collection.contentOffset.y, -18, accuracy: 2)
        XCTAssertEqual(positioned, 1)
        XCTAssertFalse(readerAtEnd, "Restoring history must not acknowledge unread messages at the end")
        controller.scrollViewDidEndDragging(collection, willDecelerate: false)
        XCTAssertEqual(remembered?.0, 250)
        XCTAssertEqual(try XCTUnwrap(remembered?.1), -18, accuracy: 2)
    }

    @MainActor func testLargeHistoryVirtualizesAndPreservesReadersAnchorOnAppend() async throws {
        let controller = ChatTimelineController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        var rows = (0..<1000).map { index in
            ChatTimelineRow(id: "row:\(index)", kind: .message, value: .object([
                "seq": .number(Double(index)), "authorKind": .string("person"), "author": .string("me"),
                "mine": .bool(true), "text": .string("Message \(index)")]))
        }
        controller.update(rows, language: "en")
        controller.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 150_000_000)
        let collection = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? UICollectionView }.first)
        XCTAssertEqual(collection.numberOfItems(inSection: 0), 1000)
        XCTAssertLessThan(collection.visibleCells.count, 40, "History must not instantiate a view per message")
        collection.scrollToItem(at: IndexPath(item: 500, section: 0), at: .top, animated: false)
        collection.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 150_000_000)
        let anchor = try XCTUnwrap(collection.indexPathsForVisibleItems.sorted().first)
        let before = try XCTUnwrap(collection.layoutAttributesForItem(at: anchor)).frame.minY - collection.contentOffset.y
        XCTAssertLessThan(anchor.item, 999)
        rows.append(ChatTimelineRow(id: "new", kind: .message, value: .object(["authorKind": .string("agent"), "text": .string("New reply")])))
        controller.update(rows, language: "en")
        try await Task.sleep(nanoseconds: 150_000_000)
        collection.layoutIfNeeded()
        let after = try XCTUnwrap(collection.layoutAttributesForItem(at: anchor)).frame.minY - collection.contentOffset.y
        XCTAssertEqual(before, after, accuracy: 2, "Appending a reply must not pull a reader away from older messages")
        XCTAssertLessThan(collection.visibleCells.count, 40)
    }

    @MainActor func testBusyTransitionReconfiguresExistingPaginationButton() async throws {
        let controller = ChatTimelineController()
        controller.loadViewIfNeeded(); controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 200)
        let rows = [ChatTimelineRow(id: "older", kind: .older)]
        controller.busy = false; controller.update(rows, language: "en"); controller.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 50_000_000)
        let collection = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? UICollectionView }.first)
        func buttons(_ view: UIView) -> [UIButton] { (view as? UIButton).map { [$0] } ?? view.subviews.flatMap(buttons) }
        let button = try XCTUnwrap(collection.visibleCells.flatMap(buttons).first)
        XCTAssertTrue(button.isEnabled)
        controller.busy = true; controller.update(rows, language: "en")
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(button.isEnabled)
    }
}
