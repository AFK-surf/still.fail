import Foundation

/// A tool step drawn by what it is, as web/src/ToolStep.tsx does: a command as a command,
/// an edit as a diff, a written file as code, a plan as a checklist, anything else as fields.
/// The result is Markdown, so the native renderer supplies highlighting, tables and selection.
enum ToolStepRendering {
    private final class Entry { let text: String; init(_ text: String) { self.text = text } }
    private static let cache: NSCache<NSString, Entry> = {
        let cache = NSCache<NSString, Entry>(); cache.countLimit = 128; cache.totalCostLimit = 8 * 1024 * 1024; return cache
    }()
    private static func key(_ row: HistoryTimelineRow) -> NSString {
        [row.toolCall == nil ? "call" : "result", row.toolName ?? "", row.toolFailed ? "1" : "0", row.toolSaid ? "1" : "0",
         row.toolCall ?? "", row.text].joined(separator: "\u{001F}") as NSString
    }
    static func cached(_ row: HistoryTimelineRow) -> String? { cache.object(forKey: key(row))?.text }
    static func render(_ row: HistoryTimelineRow) -> String {
        if let cached = cached(row) { return cached }
        let name = row.toolName ?? ""
        let rendered = row.toolCall.map { result(row.text, name: name, call: $0, failed: row.toolFailed) }
            ?? call(row.text, name: name, said: row.toolSaid)
        cache.setObject(Entry(rendered), forKey: key(row), cost: rendered.utf8.count)
        return rendered
    }

    /// Arguments are data: their asterisks and underscores must not become emphasis.
    private static func escape(_ text: String) -> String {
        var escaped = ""
        for character in text {
            if "\\`*_[]<>#|~".contains(character) { escaped.append("\\") }
            escaped.append(character)
        }
        return escaped
    }
    private static func parse(_ text: String) -> Any? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("["), let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
    private static func language(of path: String?) -> String {
        guard let path, path.contains("."), let ext = path.split(separator: ".").last?.lowercased() else { return "text" }
        return ["mjs": "js", "cjs": "js", "mts": "ts", "yml": "yaml", "zsh": "sh", "bash": "sh", "h": "c", "hpp": "cpp"][ext] ?? ext
    }
    /// A command as it would be typed: `["bash", "-lc", "ls"]` is `ls`.
    private static func command(_ args: [String: Any]) -> String? {
        let raw = args["command"] ?? args["cmd"]
        if let text = raw as? String { return text }
        guard let parts = raw as? [String], let first = parts.first else { return nil }
        let shell = ["sh", "bash", "zsh"].contains(first.split(separator: "/").last.map(String.init) ?? first)
        return shell && parts.count > 2 && parts[1] == "-lc" ? parts.dropFirst(2).joined(separator: " ") : parts.joined(separator: " ")
    }
    private static func path(_ text: String, extra: String? = nil) -> String {
        "**" + escape(text) + "**" + (extra.map { " · " + $0 } ?? "")
    }
    /// The small facts beside the main thing (a timeout, a directory, a flag).
    private static func facts(_ args: [String: Any], skip: Set<String>) -> String? {
        let rows = args.keys.sorted().compactMap { key -> String? in
            guard !skip.contains(key), let value = args[key] else { return nil }
            if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? escape(key) : nil }
            if value is String || value is NSNumber { return "\(escape(key)) \(escape("\(value)"))" }
            return nil
        }
        return rows.isEmpty ? nil : rows.joined(separator: " · ")
    }
    /// Lines taken out and put in, with the lines both share at the ends as context.
    private static func diff(_ from: String, _ to: String) -> String {
        let a = from.components(separatedBy: "\n"), b = to.components(separatedBy: "\n")
        var head = 0
        while head < a.count && head < b.count && a[head] == b[head] { head += 1 }
        var tail = 0
        while tail < a.count - head && tail < b.count - head && a[a.count - 1 - tail] == b[b.count - 1 - tail] { tail += 1 }
        let lines = a[0..<head].map { " " + $0 } + a[head..<(a.count - tail)].map { "-" + $0 }
            + b[head..<(b.count - tail)].map { "+" + $0 } + a[(a.count - tail)...].map { " " + $0 }
        return HistoryRendering.fence(lines.joined(separator: "\n"), language: "diff")
    }
    /// Fields one to a row: short ones inline, long text as a block, nested data as JSON.
    private static func fields(_ args: [String: Any], skip: Set<String>) -> String {
        let rows = args.keys.sorted().compactMap { key -> String? in
            guard !skip.contains(key), let value = args[key], !(value is NSNull) else { return nil }
            if let text = value as? String {
                if text.isEmpty { return nil }
                return text.contains("\n") || text.count > 120 ? "**\(key)**\n\n" + HistoryRendering.fence(text, language: "text") : "**\(key)** \(text)"
            }
            if value is NSNumber { return "**\(key)** \(value)" }
            if let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
               let json = String(data: data, encoding: .utf8) {
                return "**\(key)**\n\n" + HistoryRendering.fence(json, language: "json")
            }
            return nil
        }
        return rows.isEmpty ? "_" + L10n.text("没有参数") + "_" : rows.joined(separator: "\n\n")
    }

    /// What a call asked for. `said`: its description already shows as the step's name.
    static func call(_ text: String, name: String, said: Bool) -> String {
        guard let args = parse(text) as? [String: Any] else {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("*** Begin Patch") { return HistoryRendering.fence(trimmed, language: "diff") }
            return trimmed.isEmpty ? "" : HistoryRendering.fence(text, language: name == "exec" ? "js" : "text")
        }
        let skip: Set<String> = said ? ["description"] : []
        let file = (args["file_path"] ?? args["notebook_path"] ?? args["path"]) as? String
        if let command = command(args) {
            return [HistoryRendering.fence(command, language: "sh"), facts(args, skip: skip.union(["command", "cmd"]))]
                .compactMap { $0 }.joined(separator: "\n\n")
        }
        if let file, let old = args["old_string"] as? String, let new = args["new_string"] as? String {
            return path(file, extra: args["replace_all"] as? Bool == true ? L10n.text("全部替换") : nil) + "\n\n" + diff(old, new)
        }
        if let file, let edits = args["edits"] as? [[String: Any]] {
            return ([path(file)] + edits.map { diff($0["old_string"] as? String ?? "", $0["new_string"] as? String ?? "") }).joined(separator: "\n\n")
        }
        if let file, let content = args["content"] as? String {
            return path(file) + "\n\n" + HistoryRendering.fence(content, language: language(of: file))
        }
        if let items = (args["todos"] ?? args["plan"]) as? [[String: Any]] {
            let list = items.map { item -> String in
                let status = item["status"] as? String ?? ""
                let text = (item["content"] ?? item["step"]) as? String ?? ""
                return status == "completed" ? "- [x] \(text)" : status == "in_progress" ? "- [ ] **\(text)**" : "- [ ] \(text)"
            }.joined(separator: "\n")
            return [args["explanation"] as? String, list].compactMap { $0 }.joined(separator: "\n\n")
        }
        if let prompt = args["prompt"] as? String, name == "Agent" || name == "Task" || prompt.count > 200 {
            return [facts(args, skip: skip.union(["prompt"])), prompt].compactMap { $0 }.joined(separator: "\n\n")
        }
        if let file, args.keys.allSatisfy({ ["file_path", "path", "notebook_path", "offset", "limit"].contains($0) || skip.contains($0) }) {
            let from = (args["offset"] as? NSNumber)?.intValue, count = (args["limit"] as? NSNumber)?.intValue
            let range = [from.map { L10n.format("第 %d 行起", $0) }, count.map { L10n.format("%d 行", $0) }].compactMap { $0 }.joined(separator: "，")
            return path(file, extra: range.isEmpty ? nil : range)
        }
        for key in ["pattern", "query", "url"] {
            if let main = args[key] as? String { return "**\(main)**\n\n" + fields(args, skip: skip.union([key])) }
        }
        return fields(args, skip: skip)
    }

    /// What a call gave back.
    static func result(_ text: String, name: String, call: String, failed: Bool) -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "_" + L10n.text("没有输出") + "_" }
        // Codex: how the command ended, then its output.
        let header = #"^(?:Chunk ID: .*\n)?(?:Wall time: (.*)\n)?(?:Process exited with code (-?\d+)\n)?(?:Original token count: .*\n)?Output:\n?"#
        if let range = text.range(of: header, options: .regularExpression) {
            let head = String(text[range])
            let code = head.range(of: #"(?<=exited with code )-?\d+"#, options: .regularExpression).map { String(head[$0]) }
            let time = head.range(of: #"(?<=Wall time: ).*"#, options: .regularExpression).map { String(head[$0]) }
            if code != nil || time != nil {
                let facts = [code.map { L10n.format("退出码 %@", $0) }, time.map { L10n.format("用时 %@", $0) }]
                    .compactMap { $0 }.joined(separator: " · ")
                let output = String(text[range.upperBound...])
                return facts + "\n\n" + (output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "_" + L10n.text("没有输出") + "_" : HistoryRendering.fence(output, language: "text"))
            }
        }
        // Claude Code's Read: numbered lines, without their numbers.
        if !failed && (name == "Read" || name == "NotebookRead") {
            let numbered = #"^\s*\d+(→|\t)"#
            let lines = text.components(separatedBy: "\n").prefix { $0.range(of: numbered, options: .regularExpression) != nil }
            if !lines.isEmpty {
                let file = (parse(call) as? [String: Any]).flatMap { ($0["file_path"] ?? $0["path"]) as? String }
                let code = lines.map { $0.replacingOccurrences(of: numbered, with: "", options: .regularExpression) }.joined(separator: "\n")
                return HistoryRendering.fence(code, language: language(of: file))
            }
        }
        if !failed, let parsed = parse(text) {
            if let object = parsed as? [String: Any] { return fields(object, skip: []) }
            if let data = try? JSONSerialization.data(withJSONObject: parsed, options: [.prettyPrinted, .sortedKeys]),
               let json = String(data: data, encoding: .utf8) { return HistoryRendering.fence(json, language: "json") }
        }
        return HistoryRendering.fence(text, language: "text")
    }
}
