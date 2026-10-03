import Foundation

/// The exact JSON values exchanged with the existing in-process core.
enum JSONValue: Codable, Equatable, Sendable {
    case null, bool(Bool), number(Double), string(String)
    case array([JSONValue]), object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
    subscript(_ key: String) -> JSONValue { objectValue[key] ?? .null }
    var stringValue: String? { if case .string(let v) = self { return v }; return nil }
    var arrayValue: [JSONValue] { if case .array(let v) = self { return v }; return [] }
    var objectValue: [String: JSONValue] { if case .object(let v) = self { return v }; return [:] }
    var boolValue: Bool? { if case .bool(let v) = self { return v }; return nil }
    var intValue: Int? {
        guard case .number(let n) = self, n.isFinite, n.rounded() == n,
              n >= Double(Int.min), n < Double(Int.max) else { return nil }
        return Int(n)
    }
    static func from<T: Encodable>(_ value: T) throws -> JSONValue {
        try JSONDecoder().decode(Self.self, from: JSONEncoder().encode(value))
    }
    static func parse(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(Self.self, from: Data(text.utf8))
    }
    func encoded() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}

/// Same path-copying delta semantics as Android Delta.kt and docs/client-core.md.
func applyDelta(_ value: JSONValue, _ ops: [JSONValue]) -> JSONValue {
    ops.reduce(value) { current, op in
        guard case .array(let path) = op["path"] else { return current }
        return applyOp(current, op: op.objectValue, path: path[...])
    }
}

private func applyOp(_ node: JSONValue, op: [String: JSONValue], path: ArraySlice<JSONValue>) -> JSONValue {
    guard let key = path.first else {
        if let set = op["set"] { return set }
        if case .array(let items) = node, case .array(let extra) = op["append"] {
            return .array(items + extra)
        }
        return node
    }
    switch node {
    case .array(var items):
        guard let i = key.intValue, items.indices.contains(i) else { return node }
        items[i] = applyOp(items[i], op: op, path: path.dropFirst())
        return .array(items)
    case .object(var object):
        guard let name = key.stringValue else { return node }
        if path.count == 1, op["remove"] != nil { object.removeValue(forKey: name); return .object(object) }
        guard let child = object[name] ?? (path.count == 1 ? op["set"] : nil) else { return node }
        object[name] = applyOp(child, op: op, path: path.dropFirst())
        return .object(object)
    default: return node
    }
}

struct CoreFailure: Error, LocalizedError, Equatable, Sendable {
    let code: String
    let message: String
    var errorDescription: String? { L10n.text(message) }
    var outcomeUncertain: Bool { ["timeout_uncertain", "core_restarted", "cancelled_uncertain", "scope_changed"].contains(code) }
    init(code: String, message: String? = nil) {
        self.code = code.count <= 64 && code.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) ? code : "core_error"
        self.message = message ?? Self.safeMessage(self.code)
    }
    init(body: JSONValue) { self.init(code: body["code"].stringValue ?? "core_error") }
    private static func safeMessage(_ code: String) -> String {
        switch code {
        case "timeout_uncertain", "core_restarted", "cancelled_uncertain": return "连接中断，操作结果尚不确定。请先检查最新状态，再决定是否重试。"
        case "scope_changed": return "账号或工作区已切换，请在当前页面查看最新状态。"
        case "unauthorized", "not_signed_in": return "登录已失效，请重新登录。"
        case "forbidden": return "当前账号没有此操作的权限。"
        case "auth_cancelled": return "登录已取消。"
        case "secure_storage": return "无法访问安全存储，请解锁设备后重试。"
        case "not_ready": return "正在连接，请稍后重试。"
        case "auth_failed": return "未能完成登录。请重试。"
        case "apple_not_configured": return "Apple 登录暂时不可用。请重试。"
        case "login_expired", "invalid_grant": return "这次登录已过期。请重新登录。"
        case "deletion_coverage_incomplete": return "删除范围尚未完整确认，账号未被删除。"
        default: return "暂时无法完成这个操作。请重试。"
        }
    }
}

/// Reduction stays on the bridge's serial worker, including after an error.
struct CoreTopicState: Sendable {
    var value: JSONValue?
    var deltaBase: JSONValue?
    var error: CoreFailure?
    var isLoading = true
    mutating func receive(_ message: JSONValue) {
        if let body = message.objectValue["error"] {
            deltaBase = nil
            error = CoreFailure(body: body)
            isLoading = false
        } else if let whole = message.objectValue["value"] {
            value = whole; deltaBase = whole; error = nil; isLoading = false
        } else if case .array(let ops) = message["delta"], let base = deltaBase {
            let next = applyDelta(base, ops)
            value = next; deltaBase = next; error = nil; isLoading = false
        }
    }
}
