// The system's size of words (@hostapi.font_scale) as Compose applies it to sp (androidx.compose.ui.unit's
// FontScaleConverterFactory, on every Android version): at 1.03 and above not one factor but a curve, so small words
// grow by the whole scale and big ones barely (at 1.3, 8 → 10.4 but 30 → 30). A table for each of 1.15, 1.3, 1.5, 1.8
// and 2 over the same sizes, followed straight between its points (from 0 below the first; past the last, its last
// point's factor); a scale between two tables the table between them as far along; past 2, the scale as a factor; under
// 1.03, too.

///|
/// The sizes each table says what they become.
// kept across runs: a table of constants, never written
let sp_sizes : Array[Double] = [8.0, 10.0, 12.0, 14.0, 18.0, 20.0, 24.0, 30.0, 100.0]

///|
/// (scale, what sp_sizes become at it): Compose's tables.
// kept across runs: a table of constants, never written
let sp_tables : Array[(Double, Array[Double])] = [
  (1.0, sp_sizes),
  (1.15, [9.2, 11.5, 13.8, 16.4, 19.8, 21.8, 25.2, 30.0, 100.0]),
  (1.3, [10.4, 13.0, 15.6, 18.8, 21.6, 23.6, 26.4, 30.0, 100.0]),
  (1.5, [12.0, 15.0, 18.0, 22.0, 24.0, 26.0, 28.0, 30.0, 100.0]),
  (1.8, [14.4, 18.0, 21.6, 24.4, 27.6, 30.8, 32.8, 34.8, 100.0]),
  (2.0, [16.0, 20.0, 24.0, 26.0, 30.0, 34.0, 36.0, 38.0, 100.0]),
]

///|
/// Below it the scale is a factor (Compose's MinScaleForNonLinear).
let sp_curve_from : Double = 1.03

///|
/// What words of size `v` (in sp: an app's own size, as the original's `.sp`) are drawn at, at the system's `scale`.
pub fn sp_at(scale : Double, v : Double) -> Double {
  if scale < sp_curve_from || scale > 2.0 {
    return v * scale
  }
  let sign = if v < 0.0 { -1.0 } else { 1.0 }
  let a = v.abs()
  // the table at this scale: between the two it lies between, as far along as it is
  let mut k = 1
  while k < sp_tables.length() - 1 && sp_tables[k].0 < scale {
    k = k + 1
  }
  let (s0, t0) = sp_tables[k - 1]
  let (s1, t1) = sp_tables[k]
  let f = dclamp((scale - s0) / (s1 - s0), 0.0, 1.0)
  let at = fn(i : Int) { t0[i] + (t1[i] - t0[i]) * f }
  let last = sp_sizes.length() - 1
  if a >= sp_sizes[last] {
    return sign * a * (at(last) / sp_sizes[last])
  }
  let mut i = 0
  while sp_sizes[i] < a {
    i = i + 1
  }
  if sp_sizes[i] == a {
    return sign * at(i)
  }
  let (x0, y0) = if i == 0 { (0.0, 0.0) } else { (sp_sizes[i - 1], at(i - 1)) }
  sign * (y0 + (at(i) - y0) * (a - x0) / (sp_sizes[i] - x0))
}

///|
/// The size words are said at to be drawn `px`, at the system's `scale` (sp_at's inverse: its tables followed straight
/// between their points, as it does, so one is the other's way back): for words said by what they are drawn at, as a
/// node of the window's tree's are said by their size (Ctx::sp_of, Ctx::words_smaller's for them).
pub fn sp_from(scale : Double, px : Double) -> Double {
  if scale < sp_curve_from || scale > 2.0 {
    return px / scale
  }
  let sign = if px < 0.0 { -1.0 } else { 1.0 }
  let a = px.abs()
  // (sp_at grows with v: the size it draws `a` at found between two of its sizes, then straight between them)
  let mut lo = 0.0
  let mut lo_at = 0.0
  for v in sp_sizes {
    let at = sp_at(scale, v)
    if at >= a {
      return sign * (lo + (v - lo) * (if at > lo_at { (a - lo_at) / (at - lo_at) } else { 0.0 }))
    }
    lo = v
    lo_at = at
  }
  // (past the last: its last point's factor)
  sign * a * lo / lo_at
}

///|
/// The size words are said at so that this frame draws them `px` (Ctx::sp's way back, as much smaller as it says): what
/// a node of the window's tree says to be drawn as an old view's words made smaller are (Ctx::words_smaller), its size
/// said before the system's size of words applies.
pub fn Ctx::sp_of(self : Ctx, px : Double) -> Double {
  let px = px / self.words_k
  let fs = font_scale()
  if fs == 1.0 {
    px
  } else {
    sp_from(fs, px)
  }
}

///|
/// What words of size `v` (or a line, a letter spacing said with them) are drawn at, at the system's size of words
/// this frame, made as much smaller as where they are drawn says (Ctx::words_smaller) (Ctx::text, rich and editor take
/// sizes this way; what lays out round words measured by hand, too).
pub fn Ctx::sp(self : Ctx, v : Double) -> Double {
  // (the system's size of words as the frame has it, followed: what is built at it built again as it changes)
  let fs = font_scale()
  let drawn = if fs == 1.0 { v } else { sp_at(fs, v) }
  drawn * self.words_k
}

///|
/// `body`, its words (and their lines, the letter spacing said with them) drawn `k` of the size they would be: a part
/// whose words are made smaller alike to fit a room (a choice's options short of it, @sf.segmented), by what they
/// measure there (Ctx::sp). Answers what `body` does.
pub fn[T] Ctx::words_smaller(self : Ctx, k : Double, body : () -> T) -> T {
  let was = self.words_k
  self.words_k = was * k
  let out = body()
  self.words_k = was
  out
}
