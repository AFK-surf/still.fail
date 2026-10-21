// The faces still.fail's words are set in, beside the system's (docs/fonts.md): code in JetBrains Mono, as Android's
// Theme.kt JetBrainsMono, the app carrying it (font_assets.mbt, scripts/fontassets.py), given to the hosts as the app
// starts. The faces a person chooses (外观 › 字体) come later, given the same way.

///|
/// The faces the app carries, given to the hosts (@ui.face_add_bytes): the code face. Once, before the first frame.
pub fn give_faces() -> Unit {
  ignore(@ui.face_add_bytes(@host.face_code, from_b64(code_face_b64)))
}

///|
/// Bytes from base64 (what is not of its alphabet skipped: the lines' breaks).
fn from_b64(s : String) -> Bytes {
  let out : Array[Byte] = Array::new(capacity=s.length() / 4 * 3)
  let mut acc = 0
  let mut bits = 0
  for i in 0..<s.length() {
    let c = s.unsafe_charcode_at(i)
    let v = if c >= 65 && c <= 90 {
      c - 65
    } else if c >= 97 && c <= 122 {
      c - 71
    } else if c >= 48 && c <= 57 {
      c + 4
    } else if c == 43 {
      62
    } else if c == 47 {
      63
    } else {
      -1
    }
    if v < 0 {
      continue
    }
    acc = ((acc << 6) | v) & 0xFFFFFF
    bits += 6
    if bits >= 8 {
      bits -= 8
      out.push(((acc >> bits) & 0xFF).to_byte())
    }
  }
  Bytes::from_array(out)
}
