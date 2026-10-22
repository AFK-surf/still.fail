// Environment variables given as base64 (scripted runs: a script, an account's JSON), as Android's `--es env`
// (split at `;`, quoted by adb's shell) passes them whole.

///|
/// UTF-8 bytes from base64 (standard or URL-safe; padding and anything else skipped: @codec.from_base64), as text.
pub fn from_base64(s : String) -> String {
  @utf8.decode_lossy(@codec.from_base64(s)[:])
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
