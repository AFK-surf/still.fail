// The platform's own text drawing, beside mbui's, for the differential text test (src/textdiff,
// scripts/textdiff.sh): a picture drawn by the system's text engine (Core Text, Android's Canvas, DirectWrite, a
// browser's canvas) at the places mbui draws the same words, and the window's own picture, to compare the two.
// Pictures are PNGs named NAME.png in $MBUI_SHOT_DIR (Android: the app's files/textdiff; a browser keeps them for
// whoever drives the page: window.__mbref).

///|
extern "C" fn ffi_ref_begin(w : Double, h : Double, scale : Double, bg : Int) -> Unit = "mb_host_ref_begin"

///|
#borrow(text, out)
extern "C" fn ffi_ref_text(
  text : String,
  size : Double,
  weight : Int,
  style : Int,
  x : Double,
  base : Double,
  color : Int,
  out : FixedArray[Double],
) -> Unit = "mb_host_ref_text"

///|
#borrow(name)
extern "C" fn ffi_ref_end(name : String) -> Int = "mb_host_ref_end"

///|
#borrow(name)
extern "C" fn ffi_ref_frame(name : String) -> Int = "mb_host_ref_frame"

///|
/// Starts a picture `w`×`h` points at `scale` pixels a point, on a ground of `bg` (0xRRGGBB).
fn ref_begin(w : Double, h : Double, scale : Double, bg : Int) -> Unit {
  ffi_ref_begin(w, h, scale, bg)
}

///|
/// `text` drawn into it by the platform, in its system font (style: style_italic, style_mono) at `size` and
/// `weight`, starting at `x` with its baseline at `base`, in `color` (0xRRGGBB), as one line. `out`: the width it
/// advances, then its ink box (left, top, right, bottom, in points from x and the baseline, y down; all 0 if the host
/// does not say).
fn ref_text(
  text : String,
  size : Double,
  weight : Int,
  style : Int,
  x : Double,
  base : Double,
  color : Int,
  out : FixedArray[Double],
) -> Unit {
  ffi_ref_text(text, size, weight, style, x, base, color, out)
}

///|
/// The picture written as `name`.png.
fn ref_end(name : String) -> Bool {
  ffi_ref_end(name) != 0
}

///|
/// The window's picture as `name`.png: the frame last drawn, or (Android, a browser) the one drawn next; the caller
/// keeps both the same.
fn ref_frame(name : String) -> Bool {
  ffi_ref_frame(name) != 0
}
