import Foundation
import Security

/// Only this application's service is touched. No preferences, access group,
/// synchronization or plaintext fallback. Safe on foreign storage threads.
final class KeychainStorage: SecureStorage, @unchecked Sendable {
    static let service = "fail.still.iphone.core"
    private let lock = NSLock()

    private func query(_ key: String? = nil) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                               kSecAttrService as String: Self.service,
                               kSecAttrSynchronizable as String: false]
        if let key { q[kSecAttrAccount as String] = key }
        return q
    }
    func get(key: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw SecureStorageError.Unavailable }
        return data
    }
    func set(key: String, value: Data) throws {
        lock.lock(); defer { lock.unlock() }
        let attributes: [String: Any] = [kSecValueData as String: value,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(query(key) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query(key).merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw SecureStorageError.Unavailable }
    }
    func delete(key: String) throws {
        lock.lock(); defer { lock.unlock() }
        let status = SecItemDelete(query(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SecureStorageError.Unavailable }
    }

    /// Missing sandbox marker means reinstall: remove ONLY our service before
    /// creating a new installation. Failure stops startup, never signs in stale.
    func prepareDirectory() throws -> URL {
        lock.lock(); defer { lock.unlock() }
        let fm = FileManager.default
        let support = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                 appropriateFor: nil, create: true)
        var directory = support.appendingPathComponent("StillFailCore", isDirectory: true)
        let marker = directory.appendingPathComponent("installation")
        if !fm.fileExists(atPath: marker.path) {
            let status = SecItemDelete(query() as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw SecureStorageError.Unavailable }
            // Any orphan cache belongs to the old identity, not a new install.
            if fm.fileExists(atPath: directory.path) { try fm.removeItem(at: directory) }
        }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var resources = URLResourceValues(); resources.isExcludedFromBackup = true
        try directory.setResourceValues(resources)
        if !fm.fileExists(atPath: marker.path) {
            try Data(UUID().uuidString.utf8).write(to: marker, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        return directory
    }
}
