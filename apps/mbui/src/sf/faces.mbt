// The faces still.fail's words are set in, beside the system's (docs/fonts.md): code in JetBrains Mono, as Android's
// Theme.kt JetBrainsMono, the app carrying its file's bytes (font_assets.mbt, scripts/fontassets.py), given to the
// hosts as the app starts. The faces a person chooses (外观 › 字体) come later, given the same way.

///|
/// The faces the app carries, given to the hosts (@ui.face_add_bytes): the code face. Once, before the first frame.
pub fn give_faces() -> Unit {
  // (in a browser it may come after the app starts: given then, sfbase's faces)
  if code_face().length() > 0 {
    ignore(@ui.face_add_bytes(@hostapi.face_code, code_face()))
  }
}

///|
/// The code face the app carries (JetBrains Mono), its file's bytes: given again where none is chosen for code, and
/// to the fonts page's 默认 (a face of its own there).
pub fn code_face() -> Bytes {
  code_face_bytes()
}

