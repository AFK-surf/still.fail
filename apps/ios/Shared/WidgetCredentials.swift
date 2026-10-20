import Foundation
import Security

/// Only the account session and the confirmed device seed cross into the widget.
/// No tokens or private keys are ever put in the App Group's files or defaults.
final class WidgetCredentials: CoreSecureStorage, @unchecked Sendable {
    static let keys: Set<String> = ["accounts", "accounts/deleted", "device"]
    private let service = "fail.still.iphone.widget-session"
    private let widget: Bool
    init(widget: Bool = true) { self.widget = widget }
    private func query(_ key: String? = nil) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccessGroup as String: WidgetSnapshot.appGroup,
            kSecAttrSynchronizable as String: false]
        if let key { q[kSecAttrAccount as String] = key }
        return q
    }
    private func read(_ key: String) throws -> Data? {
        var q = query(key); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw SecureStorageError.unavailable }
        return data
    }
    private func put(_ key: String, _ value: Data) throws {
        let attributes: [String: Any] = [kSecValueData as String: value,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(query(key) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound { status = SecItemAdd(query(key).merging(attributes) { _, new in new } as CFDictionary, nil) }
        guard status == errSecSuccess else { throw SecureStorageError.unavailable }
    }
    func get(key: String) throws -> Data? {
        guard Self.keys.contains(key) else { return nil }
        return try WidgetFiles.locked { try read(key) }
    }
    /// Migration is app-only, atomic and never overwrites a newer extension token.
    func migrate(key: String, legacy: Data?) throws -> Data? {
        try WidgetFiles.locked {
            if let current = try read(key) { return current }
            if let legacy { try put(key, legacy) }
            return legacy
        }
    }
    func set(key: String, value: Data) throws {
        guard Self.keys.contains(key), !widget || key == "accounts" else { throw SecureStorageError.unavailable }
        try WidgetFiles.locked {
            if key == "accounts" {
                let merged = try Self.merge(incoming: value, current: read(key), widget: widget)
                try put(key, merged)
            } else { try put(key, value) }
        }
    }
    func delete(key: String) throws {
        guard !widget, Self.keys.contains(key) else { throw SecureStorageError.unavailable }
        try WidgetFiles.locked {
            let status = SecItemDelete(query(key) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw SecureStorageError.unavailable }
        }
    }
    func clear() throws {
        try WidgetFiles.locked {
            let status = SecItemDelete(query() as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw SecureStorageError.unavailable }
        }
    }
    /// The widget can renew existing sessions, never add/remove accounts or undo
    /// an app sign-out. Preserve a credential another process already rotated.
    static func merge(incoming: Data, current: Data?, widget: Bool) throws -> Data {
        let next = try JSONValue.parse(String(decoding: incoming, as: UTF8.self)).arrayValue
        let old = try current.map { try JSONValue.parse(String(decoding: $0, as: UTF8.self)).arrayValue } ?? []
        let wanted = Dictionary(next.map { ($0.text("sub"), $0) }, uniquingKeysWith: { first, _ in first })
        let existing = Dictionary(old.map { ($0.text("sub"), $0) }, uniquingKeysWith: { first, _ in first })
        let order = widget ? old : next
        let result = order.map { account -> JSONValue in
            let sub = account.text("sub")
            guard let incoming = wanted[sub] else { return account }
            guard let current = existing[sub] else { return widget ? account : incoming }
            let incomingExpiry = incoming["access_expires"].numberValue ?? 0
            let currentExpiry = current["access_expires"].numberValue ?? 0
            return incomingExpiry < currentExpiry ? current : incoming
        }
        return Data(try JSONValue.array(result).encoded().utf8)
    }
}
