// Data outflow (docs/data-outflow.md): who a program at the other end of the station's outflow socket is, by the audit
// token the station took of it as it connected (its code signature as macOS checks it now). The workspace's admins
// answer its request in still.fail.
import Foundation
import Security

enum Outflow {
  /// The program with audit token `hex` (32 bytes): its path, whether its signature holds, its Team ID, signing
  /// identifier, the signing certificate's name and the app it is in. An error when it is gone.
  static func identify(_ hex: String) -> [String: Any] {
    guard let token = bytes(hex), token.count == 32 else { return ["error": "no audit token"] }
    var code: SecCode?
    guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributeAudit: token] as CFDictionary, [], &code) == errSecSuccess, let code else {
      return ["error": "the program is gone"]
    }
    var staticCode: SecStaticCode?
    SecCodeCopyStaticCode(code, [], &staticCode)
    var url: CFURL?
    var info: CFDictionary?
    if let staticCode {
      SecCodeCopyPath(staticCode, [], &url)
      SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
    }
    let signing = info as? [String: Any] ?? [:]
    let path = (url as URL?)?.path ?? ""
    let certificates = signing[kSecCodeInfoCertificates as String] as? [SecCertificate] ?? []
    let signer = certificates.first.flatMap { SecCertificateCopySubjectSummary($0) as String? }
    // macOS's own programs carry no Team ID: Apple's anchor says they are Apple's.
    var apple: SecRequirement?
    let byApple = SecRequirementCreateWithString("anchor apple" as CFString, [], &apple) == errSecSuccess && apple.map { SecCodeCheckValidity(code, [], $0) == errSecSuccess } == true
    return [
      "path": path,
      "valid": SecCodeCheckValidity(code, [], nil) == errSecSuccess,
      "teamId": signing[kSecCodeInfoTeamIdentifier as String] as? String ?? (byApple ? "Apple" : NSNull()),
      "identifier": signing[kSecCodeInfoIdentifier as String] as? String ?? NSNull(),
      "signer": signer ?? NSNull(),
      "app": app(path) ?? NSNull(),
    ]
  }

  /// The name of the app `path` is in (the outermost `.app` above it), as its bundle says it.
  static func app(_ path: String) -> String? {
    let parts = path.split(separator: "/", omittingEmptySubsequences: false)
    guard let at = parts.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
    let bundle = parts[...at].joined(separator: "/")
    let infos = Bundle(path: bundle)?.infoDictionary
    return (infos?["CFBundleDisplayName"] as? String) ?? (infos?["CFBundleName"] as? String) ?? String(parts[at].dropLast(4))
  }

  static func bytes(_ hex: String) -> Data? {
    guard hex.count % 2 == 0 else { return nil }
    var out = Data()
    var at = hex.startIndex
    while at < hex.endIndex {
      let next = hex.index(at, offsetBy: 2)
      guard let byte = UInt8(hex[at..<next], radix: 16) else { return nil }
      out.append(byte)
      at = next
    }
    return out
  }
}
