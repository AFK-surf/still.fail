// The faces still.fail's words are set in, beside the system's (docs/fonts.md): code in JetBrains Mono, as Android's
// Theme.kt JetBrainsMono, the app carrying it (font_assets.mbt, scripts/fontassets.py), given to the hosts as the app
// starts. The faces a person chooses (外观 › 字体) come later, given the same way.

///|
/// The faces the app carries, given to the hosts (@ui.face_add_bytes): the code face. Once, before the first frame.
pub fn give_faces() -> Unit {
  ignore(@ui.face_add_bytes(@hostapi.face_code, code_face()))
}

///|
/// The code face the app carries (JetBrains Mono), its file's bytes: given again where none is chosen for code, and
/// to the fonts page's 默认 (a face of its own there).
pub fn code_face() -> Bytes {
  match code_face_bytes.val {
    Some(b) => b
    None => {
      let b = @codec.from_base64(code_face_b64)
      code_face_bytes.val = Some(b)
      b
    }
  }
}

///|
// kept across runs: the same bytes once made
let code_face_bytes : Ref[Bytes?] = Ref(None)

