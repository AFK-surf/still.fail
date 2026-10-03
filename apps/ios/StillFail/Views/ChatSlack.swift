import UIKit

/// What an agent said in Slack, or was told there, among a chat's own messages.
/// A still.fail chat's agents can also talk in Slack threads; their execution
/// histories hold those words (history.rs), each placed by when it was said.
enum ChatSlack {
    struct Item: Equatable {
        let time: Double
        let row: ChatTimelineRow
    }

    static func isSlack(_ surface: String) -> Bool { !surface.isEmpty && surface != "ember" && surface != "stillfail" }

    static func time(_ message: JSONValue) -> Double? {
        message["createdAt"].numberValue ?? message["time"]["createdAt"]["at"].numberValue
    }

    /// The source mark a message row draws: `from` Slack (a person's words) or `to` it (an agent's reply).
    static func marked(_ message: JSONValue, direction: String, url: String, place: String, failed: Bool = false) -> JSONValue {
        var fields = message.objectValue
        fields["slack"] = .object(["direction": .string(direction), "url": .string(url), "place": .string(place), "failed": .bool(failed)])
        return .object(fields)
    }

    /// The agents of a still.fail chat that are also in a Slack thread; only their histories are read.
    static func historyKeys(value: JSONValue) -> [String] {
        guard !isSlack(value["thread"].text("surface")) else { return [] }
        return value["agents"].arrayValue.compactMap { agent -> String? in
            guard agent["threads"].arrayValue.contains(where: { isSlack($0.text("surface")) }) else { return nil }
            let key = agent["session"].text("key", fallback: agent.text("key"))
            return key.isEmpty ? nil : key
        }.sorted()
    }

    static func rows(value: JSONValue, histories: [String: JSONValue]) -> [Item] {
        guard !histories.isEmpty, !isSlack(value["thread"].text("surface")) else { return [] }
        // Older chat messages not loaded yet: Slack words from before them wait for them too.
        let floor = value.flag("more") ? value["messages"].arrayValue.first.flatMap(time) : nil
        var seen = Set<String>()
        var items: [(index: Int, item: Item)] = []
        for agent in value["agents"].arrayValue {
            let session = agent["session"], key = session.text("key", fallback: agent.text("key"))
            guard let history = histories[key] else { continue }
            let by: JSONValue = .object(["name": .string(session.text("agentText")), "maker": session["maker"], "runtime": session["runtime"]])
            for item in history["items"].arrayValue {
                let content = item["body"]["content"], at = item["at"].numberValue
                switch item["body"].text("kind") {
                case "received":
                    for message in content["messages"].arrayValue where isSlack(message["place"].text("surface")) {
                        let ts = message.text("key"), place = message["place"]
                        // The same Slack message reaches every agent in its thread.
                        guard seen.insert(place.text("name") + "|" + ts).inserted else { continue }
                        // A Slack message's key is its Slack timestamp: when it was said.
                        guard let when = Double(ts).map({ $0 * 1000 }) ?? at else { continue }
                        let from = message["from"], name = from.text("name")
                        let row: JSONValue = .object([
                            "authorKind": .string("person"), "author": .string(from.text("slackUser", fallback: name)),
                            "authorName": .string(name), "by": .object(["name": .string(name)]), "text": message["text"],
                            "mine": .bool(from.flag("bound")), "createdAt": .number(when)])
                        items.append((items.count, Item(time: when, row: ChatTimelineRow(id: "slack:in:\(place.text("name")):\(ts)", kind: .message,
                            value: marked(row, direction: "from", url: place.text("url"), place: place.text("name"))))))
                    }
                case "post":
                    let place = content["place"]
                    guard isSlack(place.text("surface")), let at else { continue }
                    let row: JSONValue = .object([
                        "authorKind": .string("agent"), "author": .string(key), "by": by, "text": content["text"], "createdAt": .number(at)])
                    items.append((items.count, Item(time: at, row: ChatTimelineRow(id: "slack:out:\(key):\(item.text("key"))", kind: .message,
                        value: marked(row, direction: "to", url: place.text("url"), place: place.text("name"), failed: content.flag("failed"))))))
                default: break
                }
            }
        }
        return items.filter { floor == nil || $0.item.time >= floor! }
            .sorted { $0.item.time != $1.item.time ? $0.item.time < $1.item.time : $0.index < $1.index }
            .map(\.item)
    }
}

/// The capsule under a message that says it came from Slack or went there, and opens its thread.
final class SlackSourceButton: UIButton {
    private(set) var url: URL?
    private static let logo: UIImage? = {
        guard let source = UIImage(named: "Slack") else { return nil }
        let size = CGSize(width: 12, height: 12)
        return UIGraphicsImageRenderer(size: size).image { _ in source.draw(in: CGRect(origin: .zero, size: size)) }.withRenderingMode(.alwaysOriginal)
    }()
    override init(frame: CGRect) {
        super.init(frame: frame)
        var config = UIButton.Configuration.plain()
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
        config.imagePadding = 5
        config.image = Self.logo
        config.background.backgroundColor = ChatPalette.tile
        configuration = config
        addAction(UIAction { [weak self] _ in
            guard let url = self?.url else { return }
            UIApplication.shared.open(url)
        }, for: .touchUpInside)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(_ slack: JSONValue, traits: UITraitCollection) {
        let failed = slack.flag("failed")
        let title = L10n.text(slack.text("direction") == "from" ? "来自 Slack" : failed ? "未能发送到 Slack" : "已发送到 Slack")
        let address = URL(string: slack.text("url")).flatMap { ["https", "http", "slack"].contains($0.scheme?.lowercased() ?? "") ? $0 : nil }
        url = address
        let font = UIFontMetrics(forTextStyle: .caption2).scaledFont(for: .systemFont(ofSize: 11, weight: .semibold), compatibleWith: traits)
        let color: UIColor = failed ? .systemRed : .secondaryLabel
        let text = NSMutableAttributedString(string: title, attributes: [.font: font, .foregroundColor: color])
        if address != nil, let arrow = UIImage(systemName: "arrow.up.right", withConfiguration: UIImage.SymbolConfiguration(font: font.withSize(font.pointSize * 0.8)))?.withTintColor(color, renderingMode: .alwaysOriginal) {
            text.append(NSAttributedString(string: " "))
            text.append(NSAttributedString(attachment: NSTextAttachment(image: arrow)))
        }
        configuration?.attributedTitle = AttributedString(text)
        isUserInteractionEnabled = address != nil
        accessibilityLabel = [title, slack.text("place")].filter { !$0.isEmpty }.joined(separator: ", ")
        accessibilityTraits = address != nil ? .link : .staticText
        accessibilityIdentifier = "message.slack.\(slack.text("direction"))"
    }
}
