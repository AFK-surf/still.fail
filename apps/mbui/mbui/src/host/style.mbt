// What every host shares, whatever its target.

///|
/// A font's style bits (font_metrics, shape): slanted, the monospaced (code)
/// face, the serif face.
pub let style_italic : Int = 1

///|
pub let style_mono : Int = 2

///|
/// The serif face (a reader's 宋体: Songti on Apple, Noto Serif and its CJK on Android, SimSun on Windows).
pub let style_serif : Int = 4

///|
/// Shaped with no ligatures (asked for words with letter spacing, each cluster then spaced on its own): Core Text's
/// kCTLigatureAttributeName 0, DirectWrite's liga and clig off, Android's font feature settings "'liga' 0, 'clig' 0",
/// canvas text's fontVariantLigatures none. The font is the same.
pub let style_no_ligatures : Int = 8

///|
/// What people and agents wrote (a chat's words, a composer's), set in the face registered for them (face_text) where
/// there is one, else as the app's own words are.
pub let style_words : Int = 16

///|
/// The faces a host is given (face_add) for the app's three places: its own words (every font a style says nothing
/// else of), what people wrote (style_words), code (style_mono). Faces 4 to 15 are drawn only where a style names them
/// (style_face). A place with no face registered is in the system's.
pub let face_ui : Int = 1

///|
pub let face_text : Int = 2

///|
pub let face_code : Int = 3

///|
/// How many faces a host keeps (1 to faces_most - 1).
pub let faces_most : Int = 16

///|
/// The style bits that name face `face` (1 to 15) whatever else the style says: what is set in it is in it.
pub fn style_face(face : Int) -> Int {
  (face & 15) << 8
}

///|
/// The face a style names (style_face), 0 none.
pub fn face_of_style(style : Int) -> Int {
  (style >> 8) & 15
}
