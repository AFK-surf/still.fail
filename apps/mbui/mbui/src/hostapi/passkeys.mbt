// This device's passkeys, for an app that signs a sign-in it does not make itself (still.fail's: a page of a station's
// browser seen and driven from the app asks for one, ember docs/remote-screens.md): the platform's authenticator asked
// to sign the client data the app gives for a relying party, as a browser asks it. Windows (win_passkeys.c: its WebAuthn
// API, which asks the person itself with Windows Hello, a phone or a security key, and the passkeys of a provider such
// as 1Password); macOS 14 and later in an app entitled as a browser (apple_passwords.m: AuthenticationServices, which
// makes its own client data of the challenge and origin given); none elsewhere (`passkeys` is false there).

///|
/// A signing under way (`passkey_get`).
pub struct PasskeyRun {
  priv id : Int
}

///|
/// How a signing ended: `code` 0 signed (the credential, its authenticator data, the signature and the user handle,
/// base64url, and the client data it signed where the device made its own of the one given: macOS), 1 not (the person said no, or the device has no passkey the site takes), -1 none could be asked
/// (`err` says why).
pub(all) struct PasskeyDone {
  code : Int
  credential : String
  authenticator_data : String
  signature : String
  user_handle : String
  err : String
  client_data : String
} derive(Eq, Show, Debug)

///|
/// Whether this host can ask for a passkey at all (Windows).
pub fn passkeys() -> Bool {
  wa_able()
}

///|
/// Asks the device to sign `client_data` (as it is: its hash is what is signed) for relying party `rp_id` with one of
/// the passkeys `allow` names (base64url ids; none: any of its own for `rp_id`), the person verified as
/// `user_verification` says (`required`, `preferred`, `discouraged`); None where the host asks none.
pub fn passkey_get(
  rp_id : String,
  client_data : String,
  allow : Array[String],
  user_verification : String,
) -> PasskeyRun? {
  // (to the host: the relying party, the client data, the verification, the ids in hex joined by commas, each ended
  // by a unit separator, U+001F)
  let ids = allow.map(hex_of_b64url).filter(fn(h) { h != "" }).join(",")
  let id = wa_get("\{rp_id}\u{1f}\{client_data}\u{1f}\{user_verification}\u{1f}\{ids}\u{1f}")
  if id <= 0 {
    None
  } else {
    Some({ id, })
  }
}

///|
/// How it ended, once it has; None until then. A frame is asked for as it ends, so a view can look each frame.
pub fn PasskeyRun::done(self : PasskeyRun) -> PasskeyDone? {
  (polled.val)()
  let s = wa_out(self.id)
  if s == "" {
    return None
  }
  // (from the host: its code, the credential, the authenticator data, the signature, the user handle (hex), and why
  // it failed, then the client data it made where it made its own, each ended by a unit separator)
  let parts = s.split("\u{1f}").map(fn(p) { p.to_owned() }).to_array()
  let part = fn(i : Int) { parts.get(i).unwrap_or("") }
  let code = @string.parse_int(part(0)[:]) catch { _ => -1 }
  Some({
    code,
    credential: b64url_of_hex(part(1)),
    authenticator_data: b64url_of_hex(part(2)),
    signature: b64url_of_hex(part(3)),
    user_handle: b64url_of_hex(part(4)),
    err: part(5),
    client_data: b64url_of_hex(part(6)),
  })
}

///|
/// Forgets it (the host's ask left to end by itself).
pub fn PasskeyRun::end(self : PasskeyRun) -> Unit {
  wa_end(self.id)
}

///|
let b64url_chars : String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

///|
/// Bytes said in hex (either case) as base64url without padding; "" for none, or for what is not hex.
pub fn b64url_of_hex(hex : String) -> String {
  let bytes : Array[Int] = []
  let digit = fn(c : Char) -> Int {
    if c >= '0' && c <= '9' {
      c.to_int() - '0'.to_int()
    } else if c >= 'a' && c <= 'f' {
      c.to_int() - 'a'.to_int() + 10
    } else if c >= 'A' && c <= 'F' {
      c.to_int() - 'A'.to_int() + 10
    } else {
      -1
    }
  }
  let cs = hex.to_array()
  if cs.length() % 2 != 0 {
    return ""
  }
  for i = 0; i < cs.length(); i = i + 2 {
    let hi = digit(cs[i])
    let lo = digit(cs[i + 1])
    if hi < 0 || lo < 0 {
      return ""
    }
    bytes.push(hi * 16 + lo)
  }
  let out = StringBuilder::new()
  let alphabet = b64url_chars.to_array()
  for i = 0; i < bytes.length(); i = i + 3 {
    let n = bytes.length() - i
    let b0 = bytes[i]
    let b1 = if n > 1 { bytes[i + 1] } else { 0 }
    let b2 = if n > 2 { bytes[i + 2] } else { 0 }
    out.write_char(alphabet[b0 >> 2])
    out.write_char(alphabet[((b0 & 3) << 4) | (b1 >> 4)])
    if n > 1 {
      out.write_char(alphabet[((b1 & 15) << 2) | (b2 >> 6)])
    }
    if n > 2 {
      out.write_char(alphabet[b2 & 63])
    }
  }
  out.to_string()
}

///|
/// Base64url (padded or not) as hex, lower case; "" for what is not base64url.
pub fn hex_of_b64url(s : String) -> String {
  let alphabet = b64url_chars.to_array()
  let bits = StringBuilder::new()
  let mut acc = 0
  let mut held = 0
  for c in s {
    if c == '=' {
      continue
    }
    let v = match alphabet.search(c) {
      Some(v) => v
      None => return ""
    }
    acc = ((acc << 6) | v) & 0xFFFF
    held = held + 6
    if held >= 8 {
      held = held - 8
      let b = (acc >> held) & 0xFF
      bits.write_char("0123456789abcdef".to_array()[b >> 4])
      bits.write_char("0123456789abcdef".to_array()[b & 15])
    }
  }
  bits.to_string()
}
