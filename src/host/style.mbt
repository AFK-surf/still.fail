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
