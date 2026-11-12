// A box of a height said that holds a line of words, as the system's size of words grows them: as high as their line
// drawn at that size where that is higher than the box (list_looks_at's way for a row's lines), else the box as said.

///|
/// What box_at keeps of the last it was asked: for the theme and the size of words it was asked at, the style.
priv struct WordsBoxKept {
  theme : @ui.Theme
  scale : Double
  style : @ui.Style
}

///|
/// A box `h` high styled `box`, holding a line of `words`, at the system's size of words `scale` (View::words_scale's):
/// `box` itself where their line drawn there is no higher than `h` (the default size), else `box` as high as that line.
/// Kept in `kept` for the theme it is drawn in and the size last asked: the same asked again is the same style, worked
/// out once, nothing made (each place its own `kept`, its box, height and words the same each time it asks).
fn box_at(
  kept : Ref[WordsBoxKept?],
  box : @ui.Style,
  h : Double,
  words : @ui.TextStyle,
  scale : Double,
) -> @ui.Style {
  let th = @ui.tree_theme()
  match kept.val {
    Some(k) if physical_equal(k.theme, th) && k.scale == scale => return k.style
    _ => ()
  }
  let line = words_box_high(h, words, scale)
  let style = if line > h { box.then(@ui.style(h=Fixed(line))) } else { box }
  kept.val = Some({ theme: th, scale, style })
  style
}

///|
/// How high box_at has a box `h` high holding a line of `words` at the system's size of words `scale`: that line's
/// height where it is higher, else `h`.
fn words_box_high(h : Double, words : @ui.TextStyle, scale : Double) -> Double {
  let look = @ui.style_words(words)
  let line = if look.line < 0.0 { -look.line * @ui.sp_at(scale, look.size) } else { @ui.sp_at(scale, look.line) }
  if line > h {
    line
  } else {
    h
  }
}
