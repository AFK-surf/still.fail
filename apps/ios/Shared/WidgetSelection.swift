import Foundation
import Darwin

/// Routing only. Credentials stay in the App Group's Keychain access group.
struct WidgetSelection: Codable, Equatable, Sendable {
    let account: String
    let workspace: String
    let generation: UUID
}

enum WidgetFiles {
    static var directory: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.appGroup) }
    static func selection(in directory: URL? = directory) -> WidgetSelection? {
        guard let directory, let data = try? Data(contentsOf: directory.appendingPathComponent("widget-selection.json")) else { return nil }
        return try? JSONDecoder().decode(WidgetSelection.self, from: data)
    }
    /// Serializes routing, credential mutations and snapshot commits across the
    /// app and all extension processes. Network work never holds this lock.
    static func locked<T>(in directory: URL? = directory, _ body: () throws -> T) throws -> T {
        guard let directory else { throw SecureStorageError.unavailable }
        let path = directory.appendingPathComponent("widget-state.lock")
        if !FileManager.default.fileExists(atPath: path.path) {
            FileManager.default.createFile(atPath: path.path, contents: nil,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        }
        let fd = open(path.path, O_RDWR | O_CLOEXEC)
        guard fd >= 0 else { throw SecureStorageError.unavailable }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw SecureStorageError.unavailable }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }
    static func select(account: String?, workspace: String?, in directory: URL? = directory) throws {
        try locked(in: directory) {
            guard let directory else { return }
            let url = directory.appendingPathComponent("widget-selection.json")
            guard let account, let workspace else {
                try? FileManager.default.removeItem(at: url)
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(WidgetSnapshot.fileName))
                return
            }
            let old = selection(in: directory)
            guard old?.account != account || old?.workspace != workspace else { return }
            let selection = WidgetSelection(account: account, workspace: workspace, generation: UUID())
            try JSONEncoder().encode(selection).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(WidgetSnapshot.fileName))
        }
    }
    @discardableResult
    static func commit(_ snapshot: WidgetSnapshot, for selected: WidgetSelection, in directory: URL? = directory) throws -> Bool {
        try locked(in: directory) {
            guard let directory, selection(in: directory) == selected, let data = snapshot.encoded() else { return false }
            try data.write(to: directory.appendingPathComponent(WidgetSnapshot.fileName), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        }
    }
}
