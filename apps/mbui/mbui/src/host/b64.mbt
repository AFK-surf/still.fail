// Environment variables given as base64 (scripted runs: a script, an account's JSON), as Android's `--es env`
// (split at `;`, quoted by adb's shell) passes them whole.

///|
fn b64_value(c : Int) -> Int {
  if c >= 'A'.to_int() && c <= 'Z'.to_int() {
    c - 'A'.to_int()
  } else if c >= 'a'.to_int() && c <= 'z'.to_int() {
    c - 'a'.to_int() + 26
  } else if c >= '0'.to_int() && c <= '9'.to_int() {
    c - '0'.to_int() + 52
  } else if c == '+'.to_int() || c == '-'.to_int() {
    62
  } else if c == '/'.to_int() || c == '_'.to_int() {
    63
  } else {
    -1
  }
}

///|
/// UTF-8 bytes from base64 (standard or URL-safe; padding and anything else skipped), as text.
pub fn from_base64(s : String) -> String {
  let bytes : Array[Int] = []
  let mut acc = 0
  let mut bits = 0
  for ch in s {
    let v = b64_value(ch.to_int())
    if v < 0 {
      continue
    }
    acc = ((acc << 6) | v) & 0xFFFFFF
    bits = bits + 6
    if bits >= 8 {
      bits = bits - 8
      bytes.push((acc >> bits) & 0xFF)
    }
  }
  let sb = StringBuilder()
  let mut i = 0
  let n = bytes.length()
  while i < n {
    let b = bytes[i]
    let (len, init) = if b < 0x80 {
      (1, b)
    } else if (b >> 5) == 6 {
      (2, b & 0x1F)
    } else if (b >> 4) == 14 {
      (3, b & 0x0F)
    } else if (b >> 3) == 30 {
      (4, b & 0x07)
    } else {
      (1, 0xFFFD)
    }
    let mut cp = init
    for k in 1..<len {
      cp = if i + k < n { (cp << 6) | (bytes[i + k] & 0x3F) } else { 0xFFFD }
    }
    sb.write_char(Int::unsafe_to_char(cp))
    i = i + len
  }
  sb.to_string()
}

///|
/// An environment variable, or the same name with `_B64` given as base64 (`""` when neither is set).
pub fn env_text(name : String) -> String {
  let plain = env(name)
  if plain != "" {
    plain
  } else {
    from_base64(env(name + "_B64"))
  }
}

///|
test "from_base64 decodes UTF-8 text" {
  inspect(from_base64("5L2g5aW9LCBtYmVv"), content="你好, mbeo")
  inspect(from_base64("eyJhIjoxfQ=="), content="{\"a\":1}")
}
