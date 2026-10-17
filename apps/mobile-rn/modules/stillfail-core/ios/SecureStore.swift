import Foundation
import LocalAuthentication
import Security
import UIKit

/// A `secure.*` call that failed, `code` its whole message (client/core-ts host.ts `secureGet`: `user_cancelled`, …).
struct SecureError: Error {
  let code: String
}

/// What the core keeps sealed (client/core-ts host.ts `secureGet`; docs/vault.md, "设备上的钥匙"), as the Android app's
/// SecureStore.kt keeps it, in the Keychain: each value a generic password item of its own, this device's only (never
/// backed up, never synced). Two kinds, a service each:
///  - `user: false` (`stillfail-sealed-device`): kept while the phone has been unlocked once since it started, read
///    without asking.
///  - `user: true` (`stillfail-sealed-person`): only while the phone has a passcode, and reading it takes the person
///    (Face ID, Touch ID or the passcode: LocalAuthentication's prompt, the core's `reason` in it, then the item read
///    with what the prompt unlocked). Keeping one asks nobody. Taking the passcode off makes the system delete these
///    items; a mark kept beside each (`stillfail-sealed-person-kept`) then says `key_invalidated`, as Android says
///    when the screen lock was taken off, rather than that there is none.
/// A value is read as it was kept: asked with the other `user`, it fails. `secure.ask`: the same prompt asked by itself.
final class SecureStore {
  static let shared = SecureStore()

  private static let device = "stillfail-sealed-device"
  private static let person = "stillfail-sealed-person"
  private static let kept = "stillfail-sealed-person-kept"

  /// One call at a time: one prompt at a time.
  private let queue = DispatchQueue(label: "fail.still.core.sealed")

  /// A `secure.*` call, answered on another thread: the answer's JSON and bytes, or the failure as the core reads it.
  func answer(op: String, json: String, bytes: Data?, done: @escaping (Result<(String, Data?), SecureError>) -> Void) {
    queue.async {
      do {
        done(.success(try self.answer(op: op, json: json, bytes: bytes)))
      } catch let e as SecureError {
        done(.failure(e))
      } catch {
        done(.failure(SecureError(code: "\(type(of: error)): \(error.localizedDescription)")))
      }
    }
  }

  private func answer(op: String, json: String, bytes: Data?) throws -> (String, Data?) {
    let a = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
    let reason = a["reason"] as? String ?? ""
    // Asked by itself, before what the person should mean (turning the workspace lock off): no value, no key.
    if op == "secure.ask" {
      guard locked() else { throw SecureError(code: "no_device_lock") }
      _ = try ask(reason)
      return ("{}", nil)
    }
    guard let key = a["key"] as? String else { throw SecureError(code: "IllegalArgumentException: no key") }
    let user = a["user"] as? Bool ?? false
    switch op {
    case "secure.get":
      if let value = try get(key, user: user, reason: reason) { return ("{}", value) }
      return ("{\"none\":true}", nil)
    case "secure.set":
      try set(key, value: bytes ?? Data(), user: user)
      return ("{}", nil)
    case "secure.delete":
      for service in [Self.device, Self.person, Self.kept] { SecItemDelete(item(service, key) as CFDictionary) }
      return ("{}", nil)
    default:
      throw SecureError(code: "IllegalArgumentException: no such call: \(op)")
    }
  }

  /// Whether the phone has a passcode (nothing can take the person without one).
  private func locked() -> Bool {
    LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
  }

  private func item(_ service: String, _ key: String) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
  }

  /// Whether an item is there, without reading it (and so without asking anyone).
  private func has(_ service: String, _ key: String) throws -> Bool {
    var query = item(service, key)
    let quiet = LAContext()
    quiet.interactionNotAllowed = true
    query[kSecUseAuthenticationContext as String] = quiet
    query[kSecReturnAttributes as String] = true
    let status = SecItemCopyMatching(query as CFDictionary, nil)
    switch status {
    case errSecSuccess, errSecInteractionNotAllowed: return true
    case errSecItemNotFound: return false
    default: throw failure(status, key)
    }
  }

  private func read(_ query: [String: Any], _ key: String) throws -> Data? {
    var query = query
    query[kSecReturnData as String] = true
    var out: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &out)
    switch status {
    case errSecSuccess: return (out as? Data) ?? Data()
    case errSecItemNotFound: return nil
    case errSecUserCanceled, errSecAuthFailed: throw SecureError(code: "user_cancelled")
    default: throw failure(status, key)
    }
  }

  private func get(_ key: String, user: Bool, reason: String) throws -> Data? {
    let inDevice = try has(Self.device, key)
    let inPerson = try has(Self.person, key)
    let marked = try has(Self.kept, key)
    if !inDevice && !inPerson && !marked { return nil }
    let wasUser = !inDevice
    if wasUser != user { throw SecureError(code: "IllegalArgumentException: \(key): kept with user: \(wasUser), asked with user: \(user)") }
    if !user { return try read(item(Self.device, key), key) }
    guard locked() else { throw SecureError(code: "no_device_lock") }
    // The passcode was taken off since it was kept: the system deleted it, and it cannot be read again.
    guard inPerson else { throw SecureError(code: "key_invalidated") }
    let context = try ask(reason)
    var query = item(Self.person, key)
    query[kSecUseAuthenticationContext as String] = context
    guard let value = try read(query, key) else { throw SecureError(code: "key_invalidated") }
    return value
  }

  private func set(_ key: String, value: Data, user: Bool) throws {
    if !user {
      for service in [Self.person, Self.kept] { SecItemDelete(item(service, key) as CFDictionary) }
      // Updated in place where it is there: the old value or the new one, never neither.
      let update = SecItemUpdate(item(Self.device, key) as CFDictionary, [kSecValueData as String: value] as CFDictionary)
      if update == errSecSuccess { return }
      if update != errSecItemNotFound { throw failure(update, key) }
      var add = item(Self.device, key)
      add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      add[kSecValueData as String] = value
      let status = SecItemAdd(add as CFDictionary, nil)
      if status != errSecSuccess { throw failure(status, key) }
      return
    }
    guard locked() else { throw SecureError(code: "no_device_lock") }
    var error: Unmanaged<CFError>?
    guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .userPresence, &error) else {
      throw SecureError(code: "SecAccessControl: \(error?.takeRetainedValue().localizedDescription ?? "")")
    }
    // An item that takes the person cannot be changed without them: the old one goes, the new one is added.
    for service in [Self.device, Self.person] { SecItemDelete(item(service, key) as CFDictionary) }
    var add = item(Self.person, key)
    add[kSecAttrAccessControl as String] = access
    add[kSecValueData as String] = value
    let status = SecItemAdd(add as CFDictionary, nil)
    if status != errSecSuccess { throw failure(status, key) }
    if try !has(Self.kept, key) {
      var mark = item(Self.kept, key)
      mark[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      mark[kSecValueData as String] = Data()
      let marked = SecItemAdd(mark as CFDictionary, nil)
      if marked != errSecSuccess && marked != errSecDuplicateItem { throw failure(marked, key) }
    }
  }

  /// Asks the person: Face ID, Touch ID or the passcode, `reason` in the prompt. Fails `user_cancelled` when they said
  /// no, `no_device_lock` when there is nothing to ask with, `not_in_front` when no screen of the app is. The context
  /// it returns has said yes (a Keychain read given it asks no more).
  private func ask(_ reason: String) throws -> LAContext {
    let front = DispatchQueue.main.sync { UIApplication.shared.applicationState == .active }
    guard front else { throw SecureError(code: "not_in_front") }
    let context = LAContext()
    let done = DispatchSemaphore(value: 0)
    var failed: Error?
    var yes = false
    // The system's prompt says the app's name; an empty reason is not taken.
    context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason.isEmpty ? " " : reason) { ok, error in
      yes = ok
      failed = error
      done.signal()
    }
    done.wait()
    if yes { return context }
    guard let e = failed as? LAError else { throw SecureError(code: "biometric_error: \(failed?.localizedDescription ?? "")") }
    switch e.code {
    case .userCancel, .appCancel, .systemCancel, .userFallback: throw SecureError(code: "user_cancelled")
    case .passcodeNotSet: throw SecureError(code: "no_device_lock")
    case .notInteractive: throw SecureError(code: "not_in_front")
    default: throw SecureError(code: "biometric_error: \(e.localizedDescription)")
    }
  }

  private func failure(_ status: OSStatus, _ key: String) -> SecureError {
    let message = SecCopyErrorMessageString(status, nil) as String? ?? ""
    return SecureError(code: "OSStatus \(status): \(key): \(message)")
  }
}
