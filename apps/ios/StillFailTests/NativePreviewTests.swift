import XCTest
import SwiftUI
import UIKit
@testable import StillFail

/// Preview data stays in the test target. Production still starts the real authenticated core.
private final class PreviewCoreEngine: CoreEngine, @unchecked Sendable {
    private let callback: @Sendable (UInt64, String) -> Void
    init(_ callback: @escaping @Sendable (UInt64, String) -> Void) { self.callback = callback }
    func connect() -> UInt64 { 1 }
    func disconnect(client: UInt64) {}
    func receive(client: UInt64, json: String) {
        guard let request = try? JSONValue.parse(json) else { return }
        if let call = request["call"].stringValue {
            emit(["id": request["id"], "ok": call == "draft.get" ? .object(["text": .string("")]) : .null])
        } else if let topic = request["subscribe"]["topic"].stringValue {
            emit(["id": request["id"], "value": Self.projection(topic, params: request["subscribe"])])
        }
    }
    private func emit(_ fields: [String: JSONValue]) {
        if let json = try? JSONValue.object(fields).encoded() { callback(1, json) }
    }
    private static func projection(_ name: String, params: JSONValue) -> JSONValue {
        let account: JSONValue = .object(["sub": .string("preview"), "name": .string("Jamie"), "email": .string("jamie@example.com")])
        let workspace: JSONValue = .object(["id": .string("w"), "name": .string("Apollo"), "role": .string("owner"), "stations": .number(2), "members": .number(3)])
        let model: JSONValue = .object(["model": .string("gpt-6"), "name": .string("GPT-6"), "runtimes": .array([.string("codex")])])
        let station: JSONValue = .object(["id": .string("s"), "station": .string("w/s"), "name": .string("Studio"), "online": .bool(true), "models": .array([model])])
        switch name {
        case "accounts": return .array([account])
        case "workspaces": return .array([.object(["account": account, "loaded": .bool(true), "error": .null, "workspaces": .array([workspace])])])
        case "stations": return .array([station])
        case "newChat": return .object(["stations": .array([station]), "station": station, "any": .bool(true), "model": model, "runtime": .string("codex"), "effort": .string("high"), "efforts": .array([.string("low"), .string("medium"), .string("high")]), "accounts": .array([.object(["id": .string("a"), "name": .string("Team account")])])])
        case "chats":
            var rows: [JSONValue] = []
            let titles = ["Review the iPad layout", "Improve streaming Markdown", "Prepare the next release"]
            for index in 0..<9 {
                var row: [String: JSONValue] = [:]
                row["id"] = .string("chat-\(index)"); row["session"] = row["id"]
                row["station"] = .string("w/s"); row["thread"] = .number(Double(index + 1))
                row["title"] = .string(titles[index % titles.count])
                row["stateText"] = .string("检查消息渲染和输入框布局")
                row["pinned"] = .bool(index == 0); row["unread"] = .bool(index == 1)
                row["agents"] = .array([.object(["key": .string("agent"), "runtime": .string("codex"), "model": .string("gpt-6"), "agentText": .string("GPT-6 · high"), "maker": .object(["id": .string(index % 3 == 1 ? "anthropic" : "openai"), "name": .string(index % 3 == 1 ? "Anthropic" : "OpenAI")])])])
                row["creator"] = .object(["id": .string("jamie"), "name": .string("Jamie")])
                row["people"] = .array([
                    .object(["id": .string("jamie"), "name": .string("Jamie"), "via": .string("cloud"), "shown": .object(["name": .string("Jamie"), "display": .string("You"), "mine": .bool(true)])]),
                    .object(["id": .string("alex"), "name": .string("Alex"), "via": .string("cloud"), "shown": .object(["name": .string("Alex"), "display": .string("Alex"), "mine": .bool(false)])])
                ])
                rows.append(.object(row))
            }
            return .object(["leading": .string("agents"), "days": .array([.object(["daysAgo": .number(0), "label": .string("今天"), "items": .array(rows)])]), "note": .object(["reading": .bool(false), "failing": .array([])])])
        case "chat":
            if params.text("session") == "empty" || params["thread"].intValue == 2 {
                return .object(["title": .string("Empty conversation"), "thread": .object(["id": .number(2), "surface": .string("ember")]), "messages": .array([]), "outbox": .array([]), "agents": .array([])])
            }
            if params.text("session") == "long" || params["thread"].intValue == 3 {
                let messages = (0..<80).map { index -> JSONValue in
                    .object(["seq": .number(Double(index + 1)), "authorKind": .string("agent"), "author": .string("agent"), "text": .string("### Rendering checkpoint \(index)\n\nContent must scroll **under the floating glass controls**.\n\n```swift\nlet accent = UIColor.systemOrange\nlet route = ChatRoute(station: \"w/s\", session: \"chat\")\n```\n\n| Surface | Behavior |\n| --- | --- |\n| Header | Progressive blur |\n| Composer | Native Liquid Glass |\n\n> Keep the timeline visible beneath the controls.\n"), "by": .object(["name": .string("GPT-6 · high"), "maker": .object(["id": .string("openai")])])])
                }
                return .object(["title": .string("Glass over a long conversation"), "thread": .object(["id": .number(3), "surface": .string("ember")]), "messages": .array(messages), "outbox": .array([]), "agents": .array([])])
            }
            let texts = ["我也看了输入框，长文本应该保持稳定。", "另外需要支持横屏。", "好，那这轮一起处理。", "## Layout review\n\nThe **native timeline** keeps scrolling smooth.\n\n- Reuse message cells\n- Preserve the input cursor\n\n| Device | Layout |\n| --- | --- |\n| iPhone | Stack |\n| iPad | Split |\n\n```swift\nlet layout = UICollectionViewCompositionalLayout()\n```\n\n> Ready for another pass."]
            let messages: [JSONValue] = texts.enumerated().map { index, text in .object([
                "seq": .number(Double(index + 1)), "authorKind": .string(index == 3 ? "agent" : "person"),
                "author": .string(index == 2 ? "preview" : index == 3 ? "agent" : "teammate"), "mine": .bool(index == 2),
                "text": .string(text), "quotes": .array([]), "attachments": .array([]), "createdAt": .number(1_790_000_000_000 + Double(index) * 60_000),
                "by": .object(["name": .string(index == 3 ? "Claude Opus 5.5 · high" : index == 2 ? "Jamie" : "Alex"), "maker": .object(["id": .string(index == 3 ? "anthropic" : "openai")])])
            ]) }
            return .object(["title": .string("Review the iPad layout"), "thread": .object(["id": .number(1), "surface": .string("ember")]), "messages": .array(messages), "outbox": .array([]), "agents": .array([])])
        case "history":
            let text: JSONValue = .object(["key": .string("reply"), "body": .object(["kind": .string("text"), "content": .object(["text": .string("## Execution review\n\nChecked the **native renderer**, including tables and `inline code`.\n\n| Check | Result |\n| --- | --- |\n| Composer | Aligned |\n| Timeline | Reuses cells |")])])])
            let tools: JSONValue = .object(["key": .string("tools"), "body": .object(["kind": .string("group"), "content": .object(["summary": .string("Read source and run checks"), "title": .string("2 operations completed"), "thinking": .array([]), "steps": .array([.object(["name": .string("exec_command"), "said": .string("Read the chat implementation"), "call": .string("{\"cmd\":[\"bash\",\"-lc\",\"rg ChatTimeline\"],\"timeout_ms\":10000}"), "result": .string("Wall time: 0.4s\nProcess exited with code 0\nOutput:\nChatTimelineController uses reusable native cells."), "failed": .bool(false)]), .object(["name": .string("Edit"), "call": .string("{\"file_path\":\"Chat.swift\",\"old_string\":\"let gap = 4\",\"new_string\":\"let gap = 14\"}"), "result": .string("ok"), "failed": .bool(false)])])])])])
            return .object(["loaded": .bool(true), "empty": .bool(false), "more": .bool(false), "items": .array([text, tools]), "live": .array([]), "usage": .array([.object(["label": .string("Context"), "value": .string("12,400 tokens")])])])
        default: return .null
        }
    }
}

@MainActor
final class NativePreviewTests: XCTestCase {
    private func store() async throws -> AppStore {
        let store = AppStore(engineFactory: { PreviewCoreEngine($0) }, callTimeout: .seconds(2))
        for _ in 0..<100 {
            if store.isReady && !store.workspaceGroups.isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        try store.switchWorkspace(workspace: "w", account: "preview")
        return store
    }

    func testNativeScreensRenderWithComposerAtDeviceSize() async throws {
        let store = try await store()
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return XCTFail("No simulator window scene") }
        let previousKey = scene.windows.first(where: \.isKeyWindow)
        defer { previousKey?.makeKey() }
        let screens: [(String, AnyView)] = [
            ("conversations", AnyView(ConversationsView(workspace: "w"))),
            ("new-chat", AnyView(NavigationStack { NewChatView(workspace: "w", onCreated: { _ in }) })),
            ("chat-markdown", AnyView(NavigationStack { ChatView(route: ChatRoute(station: "w/s", session: "chat", thread: 1), workspace: "w") })),
            ("chat-empty", AnyView(NavigationStack { ChatView(route: ChatRoute(station: "w/s", session: "empty", thread: 2), workspace: "w") })),
            ("chat-glass-over-content", AnyView(NavigationStack { ChatView(route: ChatRoute(station: "w/s", session: "long", thread: 3), workspace: "w") })),
            ("execution-history", AnyView(NavigationStack { ExecutionHistoryView(station: "w/s", key: "preview-agent") })),
            ("workspaces", AnyView(NavigationStack { WorkspaceChooserView() })),
            ("chat-info", AnyView(ChatInfoSheet(route: ChatRoute(station: "w/s", session: "chat", thread: 1), workspace: "w",
                value: .object(["title": .string("Review the iPad layout"), "pinned": .bool(false), "agents": .array([.object(["key": .string("agent"), "session": .object(["key": .string("agent"), "agentText": .string("Claude Opus 5.5 · high"), "maker": .object(["id": .string("anthropic")]), "runtime": .string("claude"), "statusText": .string("空闲")]), "account": .object(["name": .string("Team account")])])])]),
                rename: {}, archive: {}, latest: {}, checkSend: nil)))
        ]
        for (name, content) in screens {
            let window = UIWindow(windowScene: scene)
            window.frame = scene.screen.bounds
            defer { window.isHidden = true }
            let host = UIHostingController(rootView: content.environment(store).environment(\.locale, Locale(identifier: "en")))
            window.rootViewController = host; window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(700))
            window.layoutIfNeeded()
            if name == "chat-glass-over-content", let collection: UICollectionView = descendant(in: host.view) {
                collection.delegate?.scrollViewWillBeginDragging?(collection)
                collection.scrollToItem(at: IndexPath(item: 42, section: 0), at: .centeredVertically, animated: false)
                try await Task.sleep(for: .milliseconds(300))
                window.layoutIfNeeded()
            }
            if name == "execution-history", let table: UITableView = descendant(in: host.view) {
                // Open the tool group, then both of its steps: a command and an edit.
                for row in [1, 2, 5] where table.numberOfRows(inSection: 0) > row {
                    table.delegate?.tableView?(table, didSelectRowAt: IndexPath(row: row, section: 0))
                    try await Task.sleep(for: .milliseconds(250))
                    window.layoutIfNeeded()
                }
                try await Task.sleep(for: .milliseconds(400))
                window.layoutIfNeeded()
            }
            if name == "conversations", let table: UITableView = descendant(in: host.view) {
                // Rows must run under the header's blur and down to the bottom edge.
                // Against the list's own column: on iPad the sidebar is an inset floating card.
                var responder: UIResponder? = table
                while let next = responder, !(next is UINavigationController) { responder = next.next }
                let column = try XCTUnwrap(responder as? UINavigationController, "The home list must live in a navigation column")
                let viewport = table.convert(table.bounds, to: window)
                let bar = column.navigationBar.convert(column.navigationBar.bounds, to: window)
                let frame = column.view.convert(column.view.bounds, to: window)
                XCTAssertLessThanOrEqual(viewport.minY, bar.minY + 1, "The home list must extend behind the header")
                XCTAssertGreaterThanOrEqual(viewport.maxY, frame.maxY - 1, "The home list must reach the column's bottom edge")
                table.setContentOffset(CGPoint(x: 0, y: table.contentOffset.y + 90), animated: false)
                try await Task.sleep(for: .milliseconds(200))
                window.layoutIfNeeded()
            }
            if name == "conversations" {
                let scope = try XCTUnwrap(edgeScope(in: host.view), "The home must own its right-edge creation gesture")
                XCTAssertFalse(scope is UIWindow)
                XCTAssertEqual(scope.bounds.width, window.bounds.width, accuracy: 2, "The edge gesture must reach the screen edge on iPad")
            } else {
                if !["execution-history", "workspaces", "chat-info"].contains(name) {
                    XCTAssertNotNil(find("composer.text", in: host.view), "\(name) must always render its input")
                }
                let bar = try XCTUnwrap(navigationBar(in: host.view), "\(name) must render its native navigation bar")
                XCTAssertFalse(bar.isHidden)
                XCTAssertFalse(bar.topItem?.title?.isEmpty ?? true, "\(name) must retain its navigation title")
                if name == "chat-empty" { XCTAssertEqual(bar.topItem?.title, "Empty conversation") }
                if name.hasPrefix("chat-"), let collection: UICollectionView = descendant(in: host.view), let surface = find("composer.inputSurface", in: host.view) {
                    let viewport = collection.convert(collection.bounds, to: window)
                    let input = surface.convert(surface.bounds, to: window)
                    let header = bar.convert(bar.bounds, to: window)
                    XCTAssertLessThanOrEqual(viewport.minY, header.minY, "Messages must extend behind the header")
                    XCTAssertGreaterThanOrEqual(viewport.maxY, input.maxY, "Messages must extend behind the glass composer")
                    XCTAssertGreaterThanOrEqual(collection.adjustedContentInset.bottom, input.height + 8, "The last message must be readable above the floating composer")
                }
                // SwiftUI's toolbar is not exposed consistently through UIKit's
                // in-process accessibility containers on iPad. Keep the actual
                // rendered toolbar in the retained screenshot for visual review.
            }
            let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
            let image = renderer.image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways
            add(attachment)
            if name == "conversations", window.traitCollection.horizontalSizeClass == .compact,
               let anchor = anchors(in: host.view).first(where: { $0.gestureName == "conversations.newChat.edge" && $0.enabled }) {
                // The right-edge page follows the finger, then settles open on a flick.
                XCTAssertNil(find("composer.bar", in: host.view))
                anchor.onPan?(EdgePan(state: .began, translation: 0, velocity: -300))
                anchor.onPan?(EdgePan(state: .changed, translation: -window.bounds.width * 0.45, velocity: -300))
                try await Task.sleep(for: .milliseconds(400))
                window.layoutIfNeeded()
                let composer = try XCTUnwrap(find("composer.bar", in: host.view), "Dragging from the right edge must mount the new chat page")
                XCTAssertEqual(composer.convert(composer.bounds, to: window).minX, window.bounds.width * 0.55 + 16, accuracy: 4, "The page must track the finger")
                let dragging = XCTAttachment(image: snapshotRenderer(window).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) })
                dragging.name = "new-chat-dragging"; dragging.lifetime = .keepAlways; add(dragging)
                anchor.onPan?(EdgePan(state: .ended, translation: -window.bounds.width * 0.45, velocity: -900))
                try await Task.sleep(for: .milliseconds(900))
                window.layoutIfNeeded()
                XCTAssertEqual(composer.convert(composer.bounds, to: window).minX, 16, accuracy: 1, "A flick must settle the page open")
                let opened = XCTAttachment(image: snapshotRenderer(window).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) })
                opened.name = "new-chat-opened"; opened.lifetime = .keepAlways; add(opened)
                // Dragging back from the left edge returns to the list.
                let back = try XCTUnwrap(anchors(in: host.view).first { $0.gestureName == "newChat.back.edge" && $0.enabled })
                back.onPan?(EdgePan(state: .began, translation: 0, velocity: 300))
                back.onPan?(EdgePan(state: .changed, translation: window.bounds.width * 0.6, velocity: 300))
                back.onPan?(EdgePan(state: .ended, translation: window.bounds.width * 0.6, velocity: 300))
                try await Task.sleep(for: .milliseconds(900))
                window.layoutIfNeeded()
                XCTAssertNil(find("composer.bar", in: host.view), "Releasing past the middle must close the page")
            }
            if name == "conversations", let table: UITableView = descendant(in: host.view), table.numberOfSections > 0, table.numberOfRows(inSection: 0) > 0 {
                table.delegate?.tableView?(table, didSelectRowAt: IndexPath(row: 0, section: 0))
                try await Task.sleep(for: .milliseconds(700))
                window.layoutIfNeeded()
                XCTAssertNotNil(find("composer.text", in: host.view), "Opening a home row must mount the actual chat detail and composer")
                let selected = renderer.image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
                let selectedAttachment = XCTAttachment(image: selected)
                selectedAttachment.name = "conversation-selected"; selectedAttachment.lifetime = .keepAlways
                add(selectedAttachment)
            }
        }
    }

    private func snapshotRenderer(_ window: UIWindow) -> UIGraphicsImageRenderer { UIGraphicsImageRenderer(bounds: window.bounds) }
    /// Edge recognizers are installed on controller views; their anchors stay in the SwiftUI tree.
    private func anchors(in view: UIView) -> [EdgePanAnchor] {
        ((view as? EdgePanAnchor).map { [$0] } ?? []) + view.subviews.flatMap { anchors(in: $0) }
    }
    private func descendant<T: UIView>(in view: UIView) -> T? {
        if let result = view as? T { return result }
        for child in view.subviews { if let result: T = descendant(in: child) { return result } }
        return nil
    }

    private func navigationBar(in view: UIView) -> UINavigationBar? {
        if let bar = view as? UINavigationBar { return bar }
        for child in view.subviews { if let bar = navigationBar(in: child) { return bar } }
        return nil
    }

    private func edgeScope(in view: UIView) -> UIView? {
        if view.gestureRecognizers?.contains(where: { $0.name == "conversations.newChat.edge" && $0.isEnabled }) == true { return view }
        for child in view.subviews { if let scope = edgeScope(in: child) { return scope } }
        return nil
    }


    private func find(_ identifier: String, in view: UIView) -> UIView? {
        if view.accessibilityIdentifier == identifier { return view }
        for child in view.subviews { if let found = find(identifier, in: child) { return found } }
        return nil
    }
}
