// How a row coming or going where it is is seen by how much of it is open: what an old list's row (ui's row_held_look)
// and a page's list's block on its way (View::scrolls_window) are both drawn by, one curve.

///|
/// How far open a row coming or going where it is has what it holds out of sight: gone by the time it is half its size,
/// not seen small (2026-10-31 the user, of 96%: 「感觉缩到 90% 不太够」「试试高度压缩过程中持续缩小」; of it seen down to
/// nothing: 「感觉缩太多也不行，或者尽量在缩到 50% 左右的时候就变成完全看不见了」; again 2026-11-08).
pub let row_gone_at : Double = 0.5

///|
/// How opaque a row coming or going where it is is drawn, `p` of it open (0 to 1): none at row_gone_at or less, whole
/// at its size, faded in between.
pub fn row_seen_at(p : Double) -> Double {
  let p = if p > 1.0 { 1.0 } else { p }
  if p <= row_gone_at {
    0.0
  } else {
    (p - row_gone_at) / (1.0 - row_gone_at)
  }
}
