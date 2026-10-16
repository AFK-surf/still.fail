#if os(macOS)
import Foundation

@available(macOS 13.0, *)
public enum PermissionFlowLocalizer {
    /// ember: the words are the host's (still.fail's station says them in its language), not a resource bundle of
    /// the package's: a helper that is one executable has no bundle beside it. A key not given is its default.
    nonisolated(unsafe) public static var words: [String: String] = [:]

    static func string(
        _ key: String,
        defaultValue: String,
        localeIdentifier: String?
    ) -> String {
        words[key] ?? defaultValue
    }
}
#endif
